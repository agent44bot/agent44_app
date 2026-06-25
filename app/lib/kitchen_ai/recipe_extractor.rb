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
    # AI generate-from-scratch is billed separately from import/extract so it
    # shows as its own line (and gets its own model toggle) on /billing.
    GENERATE_SOURCE = "nyk_recipe_generate"
    MAX_TOKENS = 4000
    # Generated recipes (multi-component dishes) run longer than extractions, so
    # give them more headroom to avoid a truncated, unparseable response.
    GENERATE_MAX_TOKENS = 8000
    BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                 "(KHTML, like Gecko) Chrome/124.0 Safari/537.36".freeze

    Result = Struct.new(:ok?, :recipes, :error, :cost_cents, keyword_init: true)

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

      chosen_model = AiModelChoice.resolve(SOURCE, default: MODEL)
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
            model:      chosen_model,
            max_tokens: MAX_TOKENS,
            system:     SYSTEM_PROMPT,
            messages:   [ { role: "user", content: build_content(text: text, pdf: pdf) } ]
          )
        end

      log = AiCallLogger.log!(response, model: chosen_model, source: SOURCE, user: @user)
      cost_cents = log&.cost_cents&.round

      recipes = parse(response)
      return Result.new(ok?: false, error: "Could not find a recipe in that text. Try pasting just the recipe.") if recipes.blank?

      Result.new(ok?: true, recipes: recipes, cost_cents: cost_cents)
    rescue Anthropic::Errors::APIError => e
      Result.new(ok?: false, error: "Anthropic: #{e.message}")
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    # Generate a DRAFT recipe from a class name + description (no source
    # document). Same output schema/parse as extract; a human reviews/edits it.
    def generate(class_name:, description: nil)
      return Result.new(ok?: false, error: "Need a class to generate a recipe.") if class_name.blank?

      chosen_model = AiModelChoice.resolve(GENERATE_SOURCE, default: MODEL)
      prompt = "Class name: #{class_name}\n\nClass description:\n#{description.to_s.strip.presence || '(none provided)'}"

      # Retry once on a transient API blip (model briefly overloaded / timeout)
      # before surfacing an error. Generation is verbose, so it gets a larger
      # token budget than extraction.
      response = with_api_retry do
        if self.class.stub
          self.class.stub.call(messages: [ { role: "user", content: [] } ])
        else
          api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
          return Result.new(ok?: false, error: "ANTHROPIC_API_KEY not set") if api_key.blank?
          Anthropic::Client.new(api_key: api_key).messages.create(
            model:      chosen_model,
            max_tokens: GENERATE_MAX_TOKENS,
            system:     GENERATE_PROMPT,
            messages:   [ { role: "user", content: prompt } ]
          )
        end
      end

      log = AiCallLogger.log!(response, model: chosen_model, source: GENERATE_SOURCE, user: @user)
      cost_cents = log&.cost_cents&.round

      recipes = parse(response)
      return Result.new(ok?: false, error: "Could not generate a recipe. Try again.") if recipes.blank?

      Result.new(ok?: true, recipes: recipes, cost_cents: cost_cents)
    rescue Anthropic::Errors::APIError => e
      Rails.logger.warn("[recipe_generate] #{e.class}: #{e.message}")
      Result.new(ok?: false, error: "The recipe generator was busy for a moment. Please try Generate again.")
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    # Revise an existing handout's recipes per a free-text instruction from
    # the user (e.g. "split the rolls into Tuna, Salmon, and Vegetarian, plus a
    # shared rice"). Returns the COMPLETE updated recipe set. Billed under the
    # same source as generate.
    def regenerate(class_name:, current_recipes:, instruction:, description: nil)
      return Result.new(ok?: false, error: "Tell the AI what to change.") if instruction.to_s.strip.blank?
      return Result.new(ok?: false, error: "No recipes to revise yet.") if Array(current_recipes).blank?

      chosen_model = AiModelChoice.resolve(GENERATE_SOURCE, default: MODEL)
      prompt = <<~MSG
        Class name: #{class_name}

        Class description:
        #{description.to_s.strip.presence || '(none provided)'}

        Current recipes (JSON):
        #{JSON.generate({ "recipes" => current_recipes })}

        Instruction:
        #{instruction.to_s.strip}
      MSG

      response = with_api_retry do
        if self.class.stub
          self.class.stub.call(messages: [ { role: "user", content: [] } ])
        else
          api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
          return Result.new(ok?: false, error: "ANTHROPIC_API_KEY not set") if api_key.blank?
          Anthropic::Client.new(api_key: api_key).messages.create(
            model:      chosen_model,
            max_tokens: GENERATE_MAX_TOKENS,
            system:     REVISE_PROMPT,
            messages:   [ { role: "user", content: prompt } ]
          )
        end
      end

      log = AiCallLogger.log!(response, model: chosen_model, source: GENERATE_SOURCE, user: @user)
      cost_cents = log&.cost_cents&.round

      recipes = parse(response)
      return Result.new(ok?: false, error: "Could not revise the recipes. Try rewording your request.") if recipes.blank?

      Result.new(ok?: true, recipes: recipes, cost_cents: cost_cents)
    rescue Anthropic::Errors::APIError => e
      Rails.logger.warn("[recipe_revise] #{e.class}: #{e.message}")
      Result.new(ok?: false, error: "The recipe assistant was busy for a moment. Please try again.")
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    private

    # Run the API call, retrying once on a transient Anthropic error (overload /
    # rate limit / 5xx / timeout) before letting it bubble to the rescue.
    def with_api_retry
      attempts = 0
      begin
        attempts += 1
        yield
      rescue Anthropic::Errors::APIError
        retry if attempts < 2
        raise
      end
    end

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You convert cooking-class recipe documents into JSON for a print layout.

      Reply with ONLY a JSON object, no prose, no code fences:
      {"recipes": [{"title": "...",
                    "ingredients": [{"qty": "2½ c", "station_qty": "1¼ c", "item": "All-purpose flour", "section": null}],
                    "directions": [{"section": null, "steps": ["..."]}]}]}

      Rules:
      - A document often contains several recipes (e.g. dough, filling, sauce); emit each as its own entry, in document order. If the document contains both a full version and an already-scaled "single station" version of the same recipes, emit each recipe ONCE using the full version's quantities.
      - qty is the full-class quantity as display text ("2½ c", "1 T", "2-3"). Standardize units to this house style: tablespoon = T, teaspoon = tsp, cup = c, gram = g, kilogram = kg, ounce = oz, pound = lb (e.g. "2 tablespoons" -> "2 T", "1/2 cup" -> "1/2 c", "1 teaspoon" -> "1 tsp", "200 grams" -> "200 g", "8 ounces" -> "8 oz"). Never convert between volume and weight, only normalize the spelling. Leave other units (ml, cloves, etc.) as written. If an ingredient has no quantity (e.g. "Salt, to taste"), use "" and put the whole line in item.
      - station_qty is the same line scaled to HALF for a single student station, as friendly kitchen text: use unicode fractions (¼ ½ ¾ ⅓), convert to smaller units when natural (1 T -> 1½ tsp when halving 1 T is awkward), scale ranges to ranges ("2-3" -> "1-2"), and leave "to taste" lines as "".
      - item is the ingredient name. Clean up punctuation artifacts from imported text so it reads naturally: drop a comma right after an opening paren ("ginger (, finely grated)" -> "ginger (finely grated)"), collapse doubled parens ("paste ((Note 2))" -> "paste (Note 2)"), and remove a stray comma right before a note ("eggplants, (small...)" -> "eggplants (small...)"). Keep the descriptive note itself; do not drop information. Use sentence case: capitalize only the first word ("KOSHER SALT" -> "Kosher salt", "olive oil" -> "Olive oil"), but keep proper nouns and brand names capitalized ("Dijon mustard", "Parmesan"). Do not use Title Case or ALL CAPS.
      - section groups ingredient lines under a sub-heading when the document has one (e.g. "Ravioli filling"); otherwise null.
      - directions: keep the document's steps verbatim, in order, grouped under their sub-headings ("Filling", "Assembly") when present; otherwise one group with section null.
      - Do not invent ingredients, steps, or quantities that are not in the document.
    PROMPT

    # For generating a draft recipe from just a class name + description. Same
    # JSON schema as SYSTEM_PROMPT, but here the model SHOULD invent a realistic
    # recipe (the opposite of the extractor's "do not invent" rule).
    GENERATE_PROMPT = <<~PROMPT.freeze
      You are a culinary instructor writing the recipe for a hands-on cooking
      class. From the class name and description, CREATE a complete, realistic
      recipe the class would teach. Emit a few related recipes (e.g. main + a
      sauce) only when the dish clearly calls for it.

      Reply with ONLY a JSON object, no prose, no code fences:
      {"recipes": [{"title": "...",
                    "ingredients": [{"qty": "2½ c", "station_qty": "1¼ c", "item": "All-purpose flour", "section": null}],
                    "directions": [{"section": null, "steps": ["..."]}]}]}

      Rules:
      - Invent sensible quantities and clear steps that fit the dish. qty is a full-class batch as display text.
      - Unit house style: tablespoon = T, teaspoon = tsp, cup = c, gram = g, kilogram = kg, ounce = oz, pound = lb. If a line has no quantity ("Salt, to taste"), use "" and put the whole line in item.
      - station_qty is the same line scaled to HALF for a single student station, friendly kitchen text (unicode fractions ¼ ½ ¾ ⅓); leave "to taste" lines as "".
      - item is the ingredient name in sentence case (capitalize only the first word; keep proper nouns and brands capitalized). No Title Case or ALL CAPS.
      - section groups ingredient lines under a sub-heading (e.g. "Sauce") or null.
      - directions: clear steps grouped by section when natural, else one group with section null.
      - This is a draft for an instructor to review and edit, so keep it realistic and concise.
    PROMPT

    # For revising an existing recipe set per a free-text instruction. Same
    # JSON schema; returns the COMPLETE updated set, applying the change and
    # inventing any new content the instruction calls for.
    REVISE_PROMPT = <<~PROMPT.freeze
      You are a culinary instructor revising the recipes for a hands-on cooking
      class. You are given the class info, the CURRENT recipes as JSON, and an
      instruction describing the change. Apply the instruction and return the
      COMPLETE updated set of recipes.

      Reply with ONLY a JSON object, no prose, no code fences:
      {"recipes": [{"title": "...",
                    "ingredients": [{"qty": "2½ c", "station_qty": "1¼ c", "item": "All-purpose flour", "section": null}],
                    "directions": [{"section": null, "steps": ["..."]}]}]}

      Rules:
      - Apply the instruction. You MAY add, remove, split, or merge recipes as it requires (e.g. split one rolls recipe into separate Tuna, Salmon, and Vegetarian recipes plus a shared rice). Keep unrelated recipes and lines unchanged.
      - Return EVERY recipe that should remain, not just the changed ones.
      - Invent sensible quantities and steps for any new recipes/lines the instruction introduces.
      - Unit house style: tablespoon = T, teaspoon = tsp, cup = c, gram = g, kilogram = kg, ounce = oz, pound = lb. If a line has no quantity ("Salt, to taste"), use "" and put the whole line in item.
      - station_qty is the same line scaled to HALF for a single student station, friendly kitchen text (unicode fractions ¼ ½ ¾ ⅓); leave "to taste" lines as "".
      - item is the ingredient name in sentence case (capitalize only the first word; keep proper nouns and brands capitalized). No Title Case or ALL CAPS.
      - section groups ingredient lines under a sub-heading or null.
      - directions: clear steps grouped by section when natural, else one group with section null.
    PROMPT

    # Fetch a recipe page and return its readable text, or a Result on error.
    # SSRF guard: only public http(s); reject localhost / private / link-local
    # hosts so this can't be pointed at internal services.
    def fetch_url(url)
      body = http_get(url.strip)
      return body if body.is_a?(Result) # validation / fetch error

      # Prefer the page's JSON-LD Recipe schema (recipeIngredient +
      # recipeInstructions). Nearly every recipe site embeds it, and it carries
      # the full ingredient list regardless of how far down the page the recipe
      # card sits, which plain tag-stripping (capped for prompt size) misses.
      structured = recipe_from_jsonld(body)
      return structured if structured.present?

      text = ActionController::Base.helpers.strip_tags(body)
      text = CGI.unescapeHTML(text).gsub(/\s+\n/, "\n").gsub(/[ \t]{2,}/, " ").strip
      return Result.new(ok?: false, error: "That page had no readable recipe text.") if text.blank?

      text[0, 16_000] # fallback for pages with no JSON-LD; bounded for prompt size
    rescue => e
      Result.new(ok?: false, error: "Could not load that page: #{e.message}")
    end

    # Pull every JSON-LD block, find Recipe object(s), and render them as plain
    # recipe text (name, ingredients, steps) for the extractor. Returns nil when
    # the page has no usable Recipe schema.
    def recipe_from_jsonld(html)
      blocks = html.scan(%r{<script[^>]+type=["']application/ld\+json["'][^>]*>(.*?)</script>}mi).flatten
      recipes = blocks.flat_map { |raw| jsonld_recipes(safe_json(raw)) }.compact
      return nil if recipes.empty?

      recipes.filter_map { |r| render_jsonld_recipe(r) }.join("\n\n").presence
    end

    def safe_json(raw)
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end

    # Walk a parsed JSON-LD value (object, @graph, or array) for Recipe nodes.
    def jsonld_recipes(node)
      case node
      when Array then node.flat_map { |n| jsonld_recipes(n) }
      when Hash
        return jsonld_recipes(node["@graph"]) if node["@graph"]
        types = Array(node["@type"]).map(&:to_s)
        types.include?("Recipe") ? [ node ] : []
      else []
      end
    end

    def render_jsonld_recipe(r)
      ingredients = Array(r["recipeIngredient"]).map { |i| CGI.unescapeHTML(i.to_s).strip }.reject(&:blank?)
      return nil if ingredients.empty?
      steps = jsonld_steps(r["recipeInstructions"])
      name  = CGI.unescapeHTML(r["name"].to_s).strip
      yield_txt = r["recipeYield"].is_a?(Array) ? r["recipeYield"].first : r["recipeYield"]
      lines = [ name.presence ].compact
      lines << "Serves: #{yield_txt}" if yield_txt.present?
      lines << "Ingredients:"
      lines.concat(ingredients.map { |i| "- #{i}" })
      if steps.any?
        lines << "Directions:"
        lines.concat(steps.each_with_index.map { |s, i| "#{i + 1}. #{s}" })
      end
      lines.join("\n")
    end

    # recipeInstructions can be a string, an array of strings, HowToStep objects,
    # or HowToSection objects wrapping steps. Flatten to step text.
    def jsonld_steps(node)
      case node
      when String then CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(node)).split(/\n+/).map(&:strip).reject(&:blank?)
      when Array  then node.flat_map { |n| jsonld_steps(n) }
      when Hash
        return jsonld_steps(node["itemListElement"]) if node["itemListElement"]
        text = node["text"] || node["name"]
        text.present? ? [ CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(text.to_s)).strip ] : []
      else []
      end
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
        Result.new(ok?: false, error: fetch_error_for(resp.code))
      end
    rescue URI::InvalidURIError
      Result.new(ok?: false, error: "That does not look like a web address.")
    end

    # Some big recipe sites (e.g. marthastewart.com / People Inc) hard-block
    # server-side fetches with 402/403/429/451 no matter the headers, so a raw
    # "(402)" reads like our bug. Point the user at the paste/PDF path, which
    # always works, instead of an arms race we can't win from a server.
    BLOCKED_FETCH_CODES = %w[401 402 403 429 451].freeze
    def fetch_error_for(code)
      if BLOCKED_FETCH_CODES.include?(code.to_s)
        "That site blocks automatic recipe import. Open the recipe, copy the " \
        "ingredients and steps, and paste them here, or upload it as a PDF."
      else
        "Could not load that page (#{code}). Try pasting the recipe text or a PDF instead."
      end
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
