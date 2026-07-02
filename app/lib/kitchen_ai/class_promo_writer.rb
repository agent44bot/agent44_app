# Writes one short social post promoting a single upcoming NY Kitchen class,
# used by ClassPromoDraftJob to pre-draft a sales push in Echo. Mirrors
# KitchenAi::GroceryAggregator: class-level stub seam for tests, every response
# logged through AiCallLogger. Billed under the existing "nyk_enhance" source
# (same job as the hub's "enhance post" button, so it shares that model choice).
#
# Returns the post body (String) or nil on any failure; the caller falls back
# to a plain template so a drafting run never dies on an API hiccup.
module KitchenAi
  class ClassPromoWriter
    MODEL      = "claude-haiku-4-5-20251001"
    SOURCE     = "nyk_enhance"
    MAX_TOKENS = 400

    class << self
      attr_accessor :stub
    end

    def initialize(user: nil)
      @user = user
    end

    def write(event)
      chosen_model = AiModelChoice.resolve(SOURCE, default: MODEL)
      response =
        if self.class.stub
          self.class.stub.call(event: event)
        else
          api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
          return nil if api_key.blank?
          Anthropic::Client.new(api_key: api_key).messages.create(
            model:      chosen_model,
            max_tokens: MAX_TOKENS,
            messages:   [ { role: "user", content: prompt(event) } ]
          )
        end

      AiCallLogger.log!(response, model: chosen_model, source: SOURCE, user: @user)
      sanitize(response.content&.first&.text.to_s).presence
    rescue => e
      Rails.logger.error("ClassPromoWriter failed: #{e.class}: #{e.message}")
      nil
    end

    private

    # House rule: no em/en dashes in AI-generated copy. Swap any the model
    # slips in for a comma so the drafted post is clean before Rich sees it.
    def sanitize(text)
      text.strip.gsub(/\s*[—–]\s*/, ", ")
    end

    def prompt(event)
      facts = [ "Class: #{event.name}",
                "When: #{event.start_at.strftime('%A, %B %-d at %-l:%M %p')}" ]
      facts << "Price: $#{event.price} per person" if event.price.present?
      facts << "Seats left: #{event.spots_left}"   if event.spots_left

      <<~PROMPT
        You write short, upbeat social posts for New York Kitchen, a cooking
        class venue in Canandaigua in the Finger Lakes wine region.

        Write ONE post promoting this class to drive ticket sales:
        #{facts.join("\n")}

        Rules:
        - Under 280 characters so it fits X and Bluesky.
        - Warm and inviting; add a little urgency when seats are limited.
        - Include the date and a clear call to book.
        - End with 2-3 relevant hashtags.
        - Do NOT use em dashes or en dashes; use commas or periods.
        - Reply with ONLY the post text: no quotes, no preamble.
      PROMPT
    end
  end
end
