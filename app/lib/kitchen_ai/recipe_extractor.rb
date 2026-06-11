# Turns a pasted class recipe (or an uploaded PDF) into the structured
# KitchenHandout data: recipes with ingredient lines and direction sections,
# plus a proposed single-station quantity for every ingredient. Quantities
# are display text on purpose (no fraction math here or in Ruby): the model
# proposes, a human reviews in the edit form.
#
# Stateless; mirrors KitchenAi::AskAgent (class-level stub for tests, every
# response logged through AiCallLogger).
module KitchenAi
  class RecipeExtractor
    # Opus: extraction + scaling judgment is quality-sensitive and runs a few
    # times a month, so the cost difference vs the app's usual Haiku is noise.
    MODEL      = "claude-opus-4-8"
    SOURCE     = "nyk_recipe_extract"
    MAX_TOKENS = 4000

    Result = Struct.new(:ok?, :recipes, :error, keyword_init: true)

    class << self
      attr_accessor :stub
    end

    def initialize(user: nil)
      @user = user
    end

    # text: pasted recipe text. pdf: raw PDF bytes (either may be nil).
    def extract(text: nil, pdf: nil)
      return Result.new(ok?: false, error: "Paste the recipe text or attach a PDF.") if text.blank? && pdf.blank?

      messages = [ { role: "user", content: build_content(text: text, pdf: pdf) } ]

      response =
        if self.class.stub
          self.class.stub.call(messages: messages)
        else
          api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
          return Result.new(ok?: false, error: "ANTHROPIC_API_KEY not set") if api_key.blank?
          client = Anthropic::Client.new(api_key: api_key)
          client.messages.create(
            model:      MODEL,
            max_tokens: MAX_TOKENS,
            system:     SYSTEM_PROMPT,
            messages:   messages
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
