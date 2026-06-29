require "base64"

# Generates a single X-length post draft for a Workspace using Claude Haiku.
# Reuses the existing AiCallLogger so usage rolls up into the same billing
# dashboard the NYK enhance flow already feeds.
module WorkspaceAi
  class Drafter
    MODEL       = "claude-haiku-4-5-20251001"
    SOURCE      = "workspace_ai_assist"
    MAX_CHARS   = 270
    MAX_TOKENS  = 400

    Result = Struct.new(:ok?, :text, :error, keyword_init: true)

    # Swap with a Proc(prompt) -> response in tests.
    class << self
      attr_accessor :stub
    end

    def initialize(workspace, user: nil)
      @workspace = workspace
      @user      = user
    end

    # When image_data (raw bytes) + image_media_type are given, the post is
    # captioned from the image using Claude's vision support — this is Brian's
    # "snap a photo, let the agent write the post" flow.
    def suggest(topic: nil, existing_draft: nil, image_data: nil, image_media_type: nil, **_ignored)
      api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
      return Result.new(ok?: false, error: "ANTHROPIC_API_KEY not set") if api_key.blank?

      has_image = image_data.present? && image_media_type.present?
      prompt    = build_prompt(topic: topic, existing_draft: existing_draft, has_image: has_image)
      content   = message_content(prompt, image_data, image_media_type)

      response =
        if self.class.stub
          self.class.stub.call(prompt)
        else
          client = Anthropic::Client.new(api_key: api_key)
          client.messages.create(
            model:      MODEL,
            max_tokens: MAX_TOKENS,
            messages:   [ { role: "user", content: content } ]
          )
        end

      AiCallLogger.log!(response, model: MODEL, source: SOURCE, user: @user, workspace: @workspace)
      text = extract_text(response)
      return Result.new(ok?: false, error: "Empty AI response") if text.blank?

      Result.new(ok?: true, text: clean(text))
    rescue Anthropic::Errors::APIError => e
      Result.new(ok?: false, error: "Anthropic: #{e.message}")
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    private

    # Builds the message content for the Anthropic call. With an image we send
    # a vision content array (image block + text prompt); otherwise plain text.
    def message_content(prompt, image_data, image_media_type)
      return prompt if image_data.blank? || image_media_type.blank?

      [
        { type: "image", source: { type: "base64", media_type: image_media_type, data: Base64.strict_encode64(image_data) } },
        { type: "text",  text: prompt }
      ]
    end

    def build_prompt(topic:, existing_draft:, has_image: false)
      <<~PROMPT
        You are a social media writer for #{@workspace.name}.
        #{brand_context}

        #{task_instruction(topic: topic, existing_draft: existing_draft, has_image: has_image)}

        Constraints:
        - Use everyday wording. No em-dashes. No greetings.
        - Maximum #{MAX_CHARS} characters total (X allows 280 — leave room for hashtags).
        - One concrete idea per post.
        - Do not wrap the post in quotes or add a preface.
        #{url_preservation_constraint(existing_draft)}

        Respond with ONLY the post text. Nothing else.
      PROMPT
    end

    # If the source draft contains URLs, instruct Claude to preserve them
    # verbatim — otherwise the "shorten for X" path will drop the link to
    # save characters, which is exactly the wrong tradeoff for a promo post.
    def url_preservation_constraint(existing_draft)
      urls = existing_draft.to_s.scan(%r{https?://[^\s)\]"<>]+}).uniq
      return "" if urls.empty?
      "- MUST preserve these URLs verbatim, do not shorten or drop them: #{urls.join(', ')}"
    end

    def brand_context
      desc = @workspace.description.to_s.strip
      return "" if desc.blank?
      "Brand context:\n#{desc}"
    end

    def task_instruction(topic:, existing_draft:, has_image: false)
      topic_s    = topic.to_s.strip
      existing_s = existing_draft.to_s.strip

      if has_image
        base = "Write a single X (Twitter) post inspired by the attached image. Describe what is genuinely in the image and tie it to the brand. Do not invent details you cannot see."
        return topic_s.present? ? %(#{base}\nAlso work in this angle/occasion: "#{topic_s}") : base
      end

      if existing_s.present? && topic_s.present?
        %(Rewrite this draft to be sharper and on-brand, taking the topic into account.\nTopic: "#{topic_s}"\nCurrent draft: "#{existing_s}")
      elsif existing_s.present?
        %(Rewrite this draft to be sharper and on-brand.\nCurrent draft: "#{existing_s}")
      elsif topic_s.present?
        %(Write a single X (Twitter) post about: "#{topic_s}")
      else
        %(Write a single X (Twitter) post that fits this brand's voice. Pick a concrete angle relevant to the brand context above.)
      end
    end

    def extract_text(response)
      if response.respond_to?(:content)
        response.content.first&.text
      elsif response.is_a?(Hash)
        response.dig(:content, 0, :text) || response.dig("content", 0, "text")
      end
    end

    def clean(text)
      # Strip surrounding quotes if Claude added them anyway; clamp length.
      stripped = text.to_s.strip.gsub(/\A["'“”‘’]+|["'“”‘’]+\z/, "")
      stripped[0, MAX_CHARS]
    end
  end
end
