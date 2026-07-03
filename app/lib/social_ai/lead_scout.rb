# Scores a social-media post as an engagement opportunity for a workspace and
# drafts a suggested reply in the brand's voice. Used by SocialListenJob on each
# fresh candidate. Mirrors KitchenAi::GroceryAggregator: class-level stub seam
# for tests, every response logged through AiCallLogger. The reply is only ever
# a suggestion; a human sends it.
module SocialAi
  class LeadScout
    # Sonnet (not Haiku) for scoring: the relevance judgment (is this really about
    # us / a bookable class, vs generic food chatter) needs the stronger model.
    # Volume is tiny (a few hundred tokens per post, capped per run), so the cost
    # is negligible. Overridable via AiModelChoice Setting "ai_model:nyk_social_scout".
    MODEL      = "claude-sonnet-4-6"
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
      You screen social media posts for a local cooking-class business and decide,
      strictly, which are genuinely worth a reply, then draft one.

      Reply with ONLY a JSON object, no prose, no code fences:
      {"score": 0-100, "reason": "short why", "reply": "the suggested reply"}

      Score HIGH (70-100) ONLY when the post clearly is one of:
      - a mention of THIS business by name or handle, or a recommendation clearly
        about it, OR
      - a real person in or near the region asking for or interested in a
        hands-on cooking class, a wine / beer / cocktail tasting, a cooking date
        night, or a similar experience they could actually book.

      Score LOW (under 30) when:
      - the post is about a DIFFERENT place, event, restaurant, or festival (e.g.
        a state fair, a specific restaurant, a concert) even if it praises "food".
      - it is generic food / travel / news / business / marketing chatter that is
        not about us and not someone looking for a class.
      - you cannot tell from the text what it refers to (e.g. a short reply
        fragment with no context). When unsure, score LOW.

      Be skeptical. Most posts are NOT a fit. A wide search feeds you a lot of
      noise and your job is to reject it. Do NOT assume a vague positive-food
      post is about this business.

      reply = only meaningful when the score is high. A friendly, genuine reply in
      the brand's voice (see BRAND), under 250 characters, no hard sell, sounds
      like a real person, and NEVER claims or implies the person was talking about
      us unless they clearly were. Do NOT use em dashes or en dashes. If the score
      is under 60, return an empty string for reply.
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
      " (New York Kitchen, a hands-on cooking class and tasting venue in " \
        "Canandaigua in the Finger Lakes wine region of upstate New York. It " \
        "offers cooking classes and wine, beer, and cocktail tastings. GOOD " \
        "targets: someone who mentions New York Kitchen, or someone in upstate " \
        "NY / the Finger Lakes area asking about or interested in a cooking " \
        "class, a wine / beer / cocktail tasting, or a cooking date night they " \
        "could book. NOT targets: general food, restaurant, fair, or travel " \
        "chatter that is not about us and is not someone looking for one of " \
        "these experiences. Warm, welcoming, community-first.)"
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
