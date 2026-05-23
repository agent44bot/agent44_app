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
        #{format_fleet_status}

        Ground rules:
        - Only answer from the data above. If something isn't there, say so plainly.
        - Be concise. When you list classes, format as one per line with the date,
          name, and availability. No tables.
        - Prices are in USD. Times shown are Eastern Time.
        - Never invent classes, prices, seat counts, or test results.
      PROMPT
    end

    # Compact summary of every sibling agent in the NYK fleet. Mirrors the
    # windowed stats the hub computes so answers match what Lora sees on
    # the dashboard.
    def format_fleet_status
      workspace = Workspace.find_by(slug: "nykitchen")
      now = Time.current
      this_week_start = now.beginning_of_week(:sunday)

      sections = [
        format_list_agent(workspace),
        format_data_agent(this_week_start),
        format_test_agent(this_week_start),
        format_display_agent(workspace),
        format_social_agent(workspace, this_week_start)
      ]
      sections.compact.join("\n\n")
    end

    def format_list_agent(_workspace)
      snapshot = KitchenSnapshot.latest
      return nil unless snapshot
      upcoming = snapshot.kitchen_events.upcoming.count
      sold_out = snapshot.kitchen_events.upcoming.count(&:sold_out?)
      this_week_actuals = KitchenSnapshot.tickets_sold_this_week_by_wday
                                          .values.compact.sum.to_i
      [
        "List Agent (calendar of upcoming classes):",
        "- #{upcoming} upcoming classes, #{sold_out} sold out",
        "- Tickets sold so far this week: #{this_week_actuals}",
        "- Snapshot date: #{snapshot.taken_on.strftime('%a %b %-d')}"
      ].join("\n")
    end

    def format_data_agent(this_week_start)
      scrape      = SmokeTestRun.nyk_scrape
      last_scrape = scrape.where(status: %w[passed failed]).order(started_at: :desc).first
      week_count  = scrape.where("started_at >= ?", this_week_start).where(status: %w[passed failed]).count
      [
        "Data Agent (scrapes the source calendar every 3h):",
        "- This week: #{week_count} successful scrape runs",
        "- Last scrape: #{last_scrape&.started_at ? time_phrase(last_scrape.started_at) : 'never'} (#{last_scrape&.status || 'n/a'})"
      ].join("\n")
    end

    def format_test_agent(this_week_start)
      nav             = SmokeTestRun.nyk_nav
      week_runs       = nav.where("started_at >= ?", this_week_start).where(status: %w[passed failed])
      week_failed     = week_runs.where(status: "failed").count
      week_total      = week_runs.count
      d30_runs        = nav.where("started_at >= ?", 30.days.ago).where(status: %w[passed failed])
      d30_total       = d30_runs.count
      d30_failed      = d30_runs.where(status: "failed").count
      d30_fail_rate   = d30_total.zero? ? 0.0 : (d30_failed.to_f / d30_total * 100).round(1)
      last_passed     = nav.where(status: "passed").order(started_at: :desc).first
      last_failed     = nav.where(status: "failed").order(started_at: :desc).first
      recent_failures = nav.where(status: "failed").order(started_at: :desc).limit(5).to_a

      lines = [
        "Test Agent (hourly smoke checks on the calendar — round-trips the page looking for breakage):",
        "- This week: #{week_total} runs, #{week_failed} failed",
        "- Last 30 days: #{d30_total} runs, #{d30_failed} failed (#{d30_fail_rate}% fail rate)",
        "- Last passed: #{last_passed&.started_at ? time_phrase(last_passed.started_at) : 'never'}",
        "- Last failed: #{last_failed&.started_at ? time_phrase(last_failed.started_at) : 'never'}"
      ]
      if recent_failures.any?
        lines << "- Recent failures:"
        recent_failures.each do |r|
          msg = (r.error_message.to_s.presence || r.summary.to_s.presence || "(no message)").truncate(160).tr("\n", " ")
          lines << "    · #{r.started_at.in_time_zone('Eastern Time (US & Canada)').strftime('%a %b %-d %-l:%M%P')} — #{msg}"
        end
      end
      lines.join("\n")
    end

    def format_display_agent(workspace)
      agent = workspace&.agent_for("display")
      return nil unless agent
      visibility = agent.setting(:visibility) || "public"
      [
        "Display Agent (in-store TV slideshow at /nykitchen/display):",
        "- Visibility: #{visibility}",
        "- Cycles #{agent.setting(:slide_count) || 5} classes, #{agent.setting(:advance_seconds) || 10}s each",
        "- Auto-refreshes every #{agent.setting(:refresh_minutes) || 10} minutes",
        "- Also prints a paper handout (Display settings → Print)"
      ].join("\n")
    end

    def format_social_agent(workspace, this_week_start)
      return nil unless workspace
      accounts = workspace.social_accounts.order(:platform).to_a
      lines = ["Social Agent (drafts + publishes posts to connected accounts):"]

      if accounts.empty?
        lines << "- No social accounts connected yet"
      else
        active_strs = accounts.map do |a|
          state = a.respond_to?(:active?) ? (a.active? ? "ok" : "needs re-auth") : "ok"
          handle = a.handle.to_s.presence ? " (#{a.handle})" : ""
          "#{a.platform.capitalize}#{handle} — #{state}"
        end
        lines << "- Connected: #{active_strs.join('; ')}"
      end

      posted_week = workspace.workspace_posts.where(status: "posted")
                              .where("posted_at >= ?", this_week_start).count
      drafts_week = workspace.workspace_drafts.where("created_at >= ?", this_week_start).count
      last_post   = workspace.workspace_posts.where(status: "posted").order(posted_at: :desc).first
      lines << "- This week: #{posted_week} posted, #{drafts_week} new drafts"
      lines << "- Last post: #{last_post&.posted_at ? time_phrase(last_post.posted_at) : 'never'}"
      lines.join("\n")
    end

    def time_phrase(t)
      delta = Time.current - t
      if delta < 1.hour
        "#{(delta / 60).round} min ago"
      elsif delta < 1.day
        "#{(delta / 3600).round} hours ago"
      elsif delta < 7.days
        "#{(delta / 86_400).round} days ago"
      else
        t.in_time_zone("Eastern Time (US & Canada)").strftime("%b %-d, %Y")
      end
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
