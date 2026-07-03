# Scores a social-media post as an engagement opportunity for a workspace and
# drafts a suggested reply in the brand's voice. Used by SocialListenJob on each
# fresh candidate. Mirrors KitchenAi::GroceryAggregator: class-level stub seam
# for tests, every response logged through AiCallLogger. The reply is only ever
# a suggestion; a human sends it.
module SocialAi
  class LeadScout
    MODEL      = "claude-haiku-4-5-20251001"
    SOURCE     = "nyk_social_scout"
    MAX_TOKENS = 500

    Result = Struct.new(:score, :reason, :reply, keyword_init: true)

    class << self
      attr_accessor :stub
    end

    def initialize(workspace:, user: nil)
      @workspace = workspace
      @user      = user
    end

    # candidate: { text:, author:, platform: }. Returns a Result or nil on
    # failure (the caller then skips the lead).
    def evaluate(candidate)
      chosen_model = AiModelChoice.resolve(SOURCE, default: MODEL)
      response =
        if self.class.stub
          self.class.stub.call(candidate: candidate)
        else
          api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
          return nil if api_key.blank?
          Anthropic::Client.new(api_key: api_key).messages.create(
            model:      chosen_model,
            max_tokens: MAX_TOKENS,
            system:     SYSTEM_PROMPT,
            messages:   [ { role: "user", content: prompt(candidate) } ]
          )
        end

      AiCallLogger.log!(response, model: chosen_model, source: SOURCE, user: @user)
      parse(response)
    rescue => e
      Rails.logger.error("SocialAi::LeadScout failed: #{e.class}: #{e.message}")
      nil
    end

    private

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You help a local cooking-class business decide which social media posts are
      worth replying to, and draft a warm, human reply.

      Reply with ONLY a JSON object, no prose, no code fences:
      {"score": 0-100, "reason": "short why", "reply": "the suggested reply"}

      score = how good an engagement opportunity this post is for the business
      (100 = clearly worth replying, 0 = irrelevant / spam / not a fit). Be
      strict: local food, cooking, date-night, or Finger Lakes interest, or a
      direct mention of the business, scores high; unrelated posts score low.
      reply = a friendly, genuine reply in the brand's voice (see BRAND). Under
      250 characters, no hard sell, sound like a real person. Do NOT use em
      dashes or en dashes; use commas or periods. If score is under 40 the reply
      may be an empty string.
    PROMPT

    def prompt(candidate)
      <<~PROMPT
        BRAND: #{@workspace.name}#{brand_context}

        POST (from #{candidate[:author]} on #{candidate[:platform]}):
        #{candidate[:text]}

        Score it and draft a reply per the rules.
      PROMPT
    end

    def brand_context
      return "" unless @workspace.slug == "nykitchen"
      " (New York Kitchen, a hands-on cooking class venue in Canandaigua in the " \
        "Finger Lakes wine region. Warm, welcoming, community-first. Great for " \
        "date nights, groups, and food lovers.)"
    end

    def parse(response)
      raw  = response.content&.first&.text.to_s
      json = raw[/\{.*\}/m]
      return nil if json.blank?
      parsed = JSON.parse(json)
      Result.new(
        score:  parsed["score"].to_i.clamp(0, 100),
        reason: sanitize(parsed["reason"]),
        reply:  sanitize(parsed["reply"])
      )
    rescue JSON::ParserError
      nil
    end

    # House rule: no em/en dashes in AI copy.
    def sanitize(text)
      text.to_s.gsub(/\s*[—–]\s*/, ", ").strip
    end
  end
end
