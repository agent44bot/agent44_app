# Generates a single X-length post draft for a Workspace using Claude Haiku.
# Reuses the existing AiCallLogger so usage rolls up into the same billing
# dashboard the NYK enhance flow already feeds.
module WorkspaceAi
  class Drafter
    MODEL       = "claude-haiku-4-5-20251001"
    SOURCE      = "workspace_ai_assist"
    MAX_CHARS   = 270
    MAX_TOKENS  = 400
    SITE_FETCH_TIMEOUT = 5
    SITE_CONTEXT_CHARS = 3000

    Result = Struct.new(:ok?, :text, :error, keyword_init: true)

    # Swap with a Proc(prompt) -> response in tests.
    class << self
      attr_accessor :stub
      # Swap with a Proc(url) -> string in tests. nil means real HTTP fetch.
      attr_accessor :site_fetch_stub
    end

    def initialize(workspace, user: nil)
      @workspace = workspace
      @user      = user
    end

    def suggest(topic: nil, existing_draft: nil, mode: nil)
      api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
      return Result.new(ok?: false, error: "ANTHROPIC_API_KEY not set") if api_key.blank?

      site_context = nil
      if mode.to_s == "site" && @workspace.source_url.present?
        site_context = fetch_site_content(@workspace.source_url)
        return Result.new(ok?: false, error: "Could not fetch #{@workspace.source_url}") if site_context.blank?
      end

      prompt = build_prompt(topic: topic, existing_draft: existing_draft, site_context: site_context)

      response =
        if self.class.stub
          self.class.stub.call(prompt)
        else
          client = Anthropic::Client.new(api_key: api_key)
          client.messages.create(
            model:      MODEL,
            max_tokens: MAX_TOKENS,
            messages:   [{ role: "user", content: prompt }]
          )
        end

      AiCallLogger.log!(response, model: MODEL, source: SOURCE, user: @user)
      text = extract_text(response)
      return Result.new(ok?: false, error: "Empty AI response") if text.blank?

      Result.new(ok?: true, text: clean(text))
    rescue Anthropic::Errors::APIError => e
      Result.new(ok?: false, error: "Anthropic: #{e.message}")
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    private

    def build_prompt(topic:, existing_draft:, site_context: nil)
      <<~PROMPT
        You are a social media writer for #{@workspace.name}.
        #{brand_context}
        #{site_block(site_context)}

        #{task_instruction(topic: topic, existing_draft: existing_draft, site_context: site_context)}

        Constraints:
        - Plain language. No em-dashes. No greetings.
        - Maximum #{MAX_CHARS} characters total (X allows 280 — leave room for hashtags).
        - One concrete idea per post.
        - Do not wrap the post in quotes or add a preface.

        Respond with ONLY the post text. Nothing else.
      PROMPT
    end

    def brand_context
      desc = @workspace.description.to_s.strip
      return "" if desc.blank?
      "Brand context:\n#{desc}"
    end

    def site_block(site_context)
      return "" if site_context.blank?
      "Live content scraped from #{@workspace.source_url}:\n#{site_context}"
    end

    def task_instruction(topic:, existing_draft:, site_context: nil)
      topic_s    = topic.to_s.strip
      existing_s = existing_draft.to_s.strip

      if existing_s.present? && topic_s.present?
        %(Rewrite this draft to be sharper and on-brand, taking the topic into account.\nTopic: "#{topic_s}"\nCurrent draft: "#{existing_s}")
      elsif existing_s.present?
        %(Rewrite this draft to be sharper and on-brand.\nCurrent draft: "#{existing_s}")
      elsif site_context.present?
        %(Write a single X (Twitter) post for this brand using a specific, current angle drawn from the live site content above. Don't reuse generic taglines; surface something concrete from the page.)
      elsif topic_s.present?
        %(Write a single X (Twitter) post about: "#{topic_s}")
      else
        %(Write a single X (Twitter) post that fits this brand's voice. Pick a concrete angle relevant to the brand context above.)
      end
    end

    def fetch_site_content(url)
      raw = if self.class.site_fetch_stub
        self.class.site_fetch_stub.call(url)
      else
        uri = URI.parse(url)
        return nil unless %w[http https].include?(uri.scheme)
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                              open_timeout: SITE_FETCH_TIMEOUT, read_timeout: SITE_FETCH_TIMEOUT) do |http|
          http.get(uri.request_uri, { "User-Agent" => "Agent44LabsBot/1.0 (+https://agent44labs.com)" })
        end
        return nil unless res.is_a?(Net::HTTPSuccess)
        res.body
      end

      ActionView::Base.full_sanitizer.sanitize(raw.to_s).gsub(/\s+/, " ").strip.first(SITE_CONTEXT_CHARS)
    rescue => e
      Rails.logger.warn("Drafter site fetch failed for #{url}: #{e.class}: #{e.message}")
      nil
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
