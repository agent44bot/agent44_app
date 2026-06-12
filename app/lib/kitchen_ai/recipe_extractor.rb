# Turns a pasted class recipe (or an uploaded PDF) into the structured
# KitchenHandout data: recipes with ingredient lines and direction sections,
# plus a proposed single-station quantity for every ingredient. Quantities
# are display text on purpose (no fraction math here or in Ruby): the model
# proposes, a human reviews in the edit form.
#
# Stateless; mirrors KitchenAi::AskAgent (class-level stub for tests, every
# response logged through AiCallLogger).
require "net/http"

module KitchenAi
  class RecipeExtractor
    # Opus: extraction + scaling judgment is quality-sensitive and runs a few
    # times a month, so the cost difference vs the app's usual Haiku is noise.
    MODEL      = "claude-opus-4-8"
    SOURCE     = "nyk_recipe_extract"
    MAX_TOKENS = 4000
    BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                 "(KHTML, like Gecko) Chrome/124.0 Safari/537.36".freeze

    Result = Struct.new(:ok?, :recipes, :error, keyword_init: true)

    class << self
      attr_accessor :stub
    end

    def initialize(user: nil)
      @user = user
    end

    # text: pasted recipe text. pdf: raw PDF bytes. url: a recipe page to fetch.
    # Any one is enough.
    def extract(text: nil, pdf: nil, url: nil)
      if text.blank? && pdf.blank? && url.blank?
        return Result.new(ok?: false, error: "Paste a recipe, add a recipe URL, or attach a PDF.")
      end

      response =
        if self.class.stub
          # Tests set the stub; never fetch a URL or call the API there.
          self.class.stub.call(messages: [ { role: "user", content: [] } ])
        else
          if url.present? && text.blank?
            fetched = fetch_url(url)
            return fetched if fetched.is_a?(Result) # SSRF/fetch error
            text = fetched
          end

          api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
          return Result.new(ok?: false, error: "ANTHROPIC_API_KEY not set") if api_key.blank?
          client = Anthropic::Client.new(api_key: api_key)
          client.messages.create(
            model:      MODEL,
            max_tokens: MAX_TOKENS,
            system:     SYSTEM_PROMPT,
            messages:   [ { role: "user", content: build_content(text: text, pdf: pdf) } ]
          )
        end

      AiCallLogger.log!(response, model: MODEL, source: SOURCE, user: @user)

      recipes = parse(response)
      return Result.new(ok?: false, error: "Could not find a recipe in that text. Try pasting just the recipe.") if recipes.blank?

      Result.new(ok?: true, recipes: recipes)
    rescue Anthropic::Errors::APIError => e
      Result.new(ok?: false, error: "Anthropic: #{e.message}")
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    private

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You convert cooking-class recipe documents into JSON for a print layout.

      Reply with ONLY a JSON object, no prose, no code fences:
      {"recipes": [{"title": "...",
                    "ingredients": [{"qty": "2½ c", "station_qty": "1¼ c", "item": "All-purpose flour", "section": null}],
                    "directions": [{"section": null, "steps": ["..."]}]}]}

      Rules:
      - A document often contains several recipes (e.g. dough, filling, sauce); emit each as its own entry, in document order. If the document contains both a full version and an already-scaled "single station" version of the same recipes, emit each recipe ONCE using the full version's quantities.
      - qty is the full-class quantity as display text ("2½ c", "1 T", "2-3"). Keep the document's units. If an ingredient has no quantity (e.g. "Salt, to taste"), use "" and put the whole line in item.
      - station_qty is the same line scaled to HALF for a single student station, as friendly kitchen text: use unicode fractions (¼ ½ ¾ ⅓), convert to smaller units when natural (1 T -> 1½ tsp when halving 1 T is awkward), scale ranges to ranges ("2-3" -> "1-2"), and leave "to taste" lines as "".
      - section groups ingredient lines under a sub-heading when the document has one (e.g. "Ravioli filling"); otherwise null.
      - directions: keep the document's steps verbatim, in order, grouped under their sub-headings ("Filling", "Assembly") when present; otherwise one group with section null.
      - Do not invent ingredients, steps, or quantities that are not in the document.
    PROMPT

    # Fetch a recipe page and return its readable text, or a Result on error.
    # SSRF guard: only public http(s); reject localhost / private / link-local
    # hosts so this can't be pointed at internal services.
    def fetch_url(url)
      body = http_get(url.strip)
      return body if body.is_a?(Result) # validation / fetch error

      text = ActionController::Base.helpers.strip_tags(body)
      text = CGI.unescapeHTML(text).gsub(/\s+\n/, "\n").gsub(/[ \t]{2,}/, " ").strip
      return Result.new(ok?: false, error: "That page had no readable recipe text.") if text.blank?

      text[0, 12_000] # plenty for a recipe; keeps the prompt bounded
    rescue => e
      Result.new(ok?: false, error: "Could not load that page: #{e.message}")
    end

    # Net::HTTP GET with a small manual redirect chain. Uses the stdlib (not a
    # gem) so it works in production; the SSRF guard re-runs on every hop so a
    # redirect can't bounce us to an internal host. Returns the body or a Result.
    def http_get(url, redirects_left: 4)
      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTP) && uri.host.present?
        return Result.new(ok?: false, error: "That does not look like a web address.")
      end
      return Result.new(ok?: false, error: "That URL is not allowed.") if private_host?(uri.host)

      resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                             open_timeout: 10, read_timeout: 15) do |http|
        # A normal browser UA: many recipe sites 403/404 unfamiliar agents,
        # and this is a user-initiated fetch of a page they pasted.
        http.get(uri.request_uri, { "User-Agent" => BROWSER_UA, "Accept" => "text/html" })
      end

      case resp
      when Net::HTTPSuccess
        resp.body.to_s
      when Net::HTTPRedirection
        return Result.new(ok?: false, error: "Too many redirects.") if redirects_left <= 0
        http_get(URI.join(uri, resp["location"]).to_s, redirects_left: redirects_left - 1)
      else
        Result.new(ok?: false, error: "Could not load that page (#{resp.code}).")
      end
    rescue URI::InvalidURIError
      Result.new(ok?: false, error: "That does not look like a web address.")
    end

    def private_host?(host)
      return true if host =~ /\A(localhost|.*\.local)\z/i
      addr = IPAddr.new(host) rescue nil
      return false unless addr # hostnames resolve at request time; allow them
      addr.loopback? || addr.private? || addr.link_local?
    end

    def build_content(text:, pdf:)
      blocks = []
      if pdf.present?
        blocks << {
          type: "document",
          source: { type: "base64", media_type: "application/pdf", data: Base64.strict_encode64(pdf) }
        }
      end
      blocks << { type: "text", text: text.presence || "Extract the recipes from the attached document." }
      blocks
    end

    def parse(response)
      raw = response.content&.first&.text.to_s
      json = raw[/\{.*\}/m] # tolerate stray prose or fences around the object
      return nil if json.blank?
      parsed = JSON.parse(json)
      recipes = parsed["recipes"]
      return nil unless recipes.is_a?(Array) && recipes.all? { |r| r.is_a?(Hash) && r["title"].present? }
      recipes
    rescue JSON::ParserError
      nil
    end
  end
end
