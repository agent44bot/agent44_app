# Read-only Q&A agent for the NY Kitchen workspace. Wraps Claude Haiku with
# a system prompt that includes the latest KitchenSnapshot data, so callers
# can ask aggregation questions ("what sold out this week", "trend on pasta
# classes") without us having to wire per-question SQL.
#
# Stateless on the server: each call accepts the full message history from
# the client and returns one reply. No persistence in v1.
module KitchenAi
  class AskAgent
    MODEL      = "claude-haiku-4-5-20251001"
    SOURCE     = "nyk_ask"
    MAX_TOKENS = 800

    Result = Struct.new(:ok?, :reply, :error, keyword_init: true)

    class << self
      attr_accessor :stub
    end

    def initialize(user: nil)
      @user = user
    end

    # messages: array of { role: "user"|"assistant", content: "..." } hashes.
    # Returns Result with the assistant's reply text.
    def ask(messages)
      messages = sanitize(messages)
      return Result.new(ok?: false, error: "No message") if messages.empty?

      api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
      return Result.new(ok?: false, error: "ANTHROPIC_API_KEY not set") if api_key.blank?

      system_prompt = build_system_prompt

      response =
        if self.class.stub
          self.class.stub.call(system_prompt: system_prompt, messages: messages)
        else
          client = Anthropic::Client.new(api_key: api_key)
          client.messages.create(
            model:      MODEL,
            max_tokens: MAX_TOKENS,
            system:     system_prompt,
            messages:   messages
          )
        end

      AiCallLogger.log!(response, model: MODEL, source: SOURCE, user: @user)

      text = extract_text(response)
      return Result.new(ok?: false, error: "Empty AI response") if text.blank?

      Result.new(ok?: true, reply: text.strip)
    rescue Anthropic::Errors::APIError => e
      Result.new(ok?: false, error: "Anthropic: #{e.message}")
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    private

    # Keep only role/content fields, drop any pending/system rows, cap at
    # the last 30 turns so a runaway tab can't blow the token budget.
    def sanitize(messages)
      Array(messages).filter_map do |m|
        m = m.with_indifferent_access if m.is_a?(Hash)
        role    = m["role"].to_s
        content = m["content"].to_s.strip
        next if content.blank?
        next unless %w[user assistant].include?(role)
        { role: role, content: content }
      end.last(30)
    end

    def build_system_prompt
      snapshot = KitchenSnapshot.latest
      taken_on = snapshot&.taken_on
      events   = snapshot ? snapshot.kitchen_events.order(:start_at).to_a : []

      upcoming = events.select { |e| e.start_at && e.start_at >= Time.current }
      sold_out_upcoming = upcoming.select(&:sold_out?)

      avg_per_day  = KitchenSnapshot.tickets_sold_daily_avg
      today_sold   = (taken_on == Date.current) ? snapshot.tickets_sold_today : nil

      <<~PROMPT
        You are Super Agent for New York Kitchen, a culinary education center in
        Canandaigua, NY. You help Lora and her team answer questions using the
        data below.

        You sit on top of the rest of NY Kitchen's agent fleet — the List Agent
        (calendar), Data Agent (scrapes the source site every 3h), Test Agent
        (round-trips the calendar hourly looking for breakage), Display Agent
        (in-store screen), and Social Agent (posts to X, Bluesky, etc.). When
        someone asks how those agents are doing, use the fleet-status section.

        Today's date: #{Date.current.strftime('%A, %B %-d, %Y')}
        Data freshness: snapshot taken #{taken_on&.strftime('%A %b %-d') || 'unknown'}

        TICKET SALES (rolling):
        - Avg tickets sold per day (last 14 days): #{avg_per_day || 'n/a'}
        - Tickets sold today so far: #{today_sold || 'n/a'}

        UPCOMING CLASSES (#{upcoming.size} total, #{sold_out_upcoming.size} sold out):
        #{format_events(upcoming)}

        AGENT FLEET STATUS:
        #{KitchenAi::FleetStatus.summary}

        Ground rules:
        - Only answer from the data above. If something isn't there, say so plainly.
        - Be concise. When you list classes, format as one per line with the date,
          name, and availability. No tables.
        - Prices are in USD. Times shown are Eastern Time.
        - Never invent classes, prices, seat counts, or test results.
      PROMPT
    end

    # Compact one-line format per event to keep the prompt tight. Roughly
    # 60-80 tokens per event, so 100 events ~ 7K tokens.
    def format_events(events)
      events.map do |e|
        date  = e.start_at&.in_time_zone("Eastern Time (US & Canada)")&.strftime("%a %b %-d %-l:%M%P") || "?"
        price = e.price.present? ? "$#{e.price}" : nil
        seats = if e.sold_out?
          "SOLD OUT"
        elsif e.spots_left.present? && e.capacity.present?
          "#{e.spots_left} of #{e.capacity} left"
        elsif e.spots_left.present?
          "#{e.spots_left} left"
        else
          e.availability.to_s.presence || "?"
        end
        [date, e.name, seats, price].compact.join(" · ")
      end.join("\n")
    end

    def extract_text(response)
      if response.respond_to?(:content)
        response.content.first&.text
      elsif response.is_a?(Hash)
        response.dig(:content, 0, :text) || response.dig("content", 0, "text")
      end
    end
  end
end
