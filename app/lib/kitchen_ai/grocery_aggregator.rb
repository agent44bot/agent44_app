# Turns a set of class recipes (with how many stations of each are booked)
# into one consolidated grocery list: ingredients scaled by station count,
# duplicates merged across classes, organized into store sections. Quantities
# are display text, so the model does the unit math and merging (the same
# reason RecipeExtractor leaves them as text) and a human sanity-checks.
#
# Stateless; mirrors KitchenAi::RecipeExtractor (class-level stub for tests,
# every response logged through AiCallLogger).
module KitchenAi
  class GroceryAggregator
    MODEL      = "claude-opus-4-8"
    SOURCE     = "nyk_grocery_list"
    MAX_TOKENS = 4000

    Result = Struct.new(:ok?, :categories, :to_taste, :cost_cents, :error, keyword_init: true)

    class << self
      attr_accessor :stub
    end

    def initialize(user: nil)
      @user = user
    end

    # items: array of { class_name:, stations:, recipes: [ KitchenHandout#recipes ] }.
    # stations is the multiplier for that class's per-station amounts.
    def build(items)
      items = Array(items).reject { |i| Array(i[:recipes]).empty? }
      return Result.new(ok?: false, error: "No classes with recipes in range.") if items.empty?

      response =
        if self.class.stub
          self.class.stub.call(items: items)
        else
          api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
          return Result.new(ok?: false, error: "ANTHROPIC_API_KEY not set") if api_key.blank?
          Anthropic::Client.new(api_key: api_key).messages.create(
            model:      MODEL,
            max_tokens: MAX_TOKENS,
            system:     SYSTEM_PROMPT,
            messages:   [ { role: "user", content: build_prompt(items) } ]
          )
        end

      log = AiCallLogger.log!(response, model: MODEL, source: SOURCE, user: @user)
      parsed = parse(response)
      return Result.new(ok?: false, error: "Could not build the list. Try again.") if parsed.nil?

      Result.new(ok?: true, categories: parsed["categories"], to_taste: parsed["to_taste"],
                 cost_cents: log&.cost_cents&.round)
    rescue Anthropic::Errors::APIError => e
      Result.new(ok?: false, error: "Anthropic: #{e.message}")
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    private

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You build a single consolidated grocery list for a kitchen's cooking classes.

      Reply with ONLY a JSON object, no prose, no code fences:
      {"categories": [{"name": "Produce", "items": [{"item": "Lemons", "quantity": "3"}]}],
       "to_taste": ["Salt", "Black pepper"]}

      Input: several classes. Each lists how many STATIONS are booked and its recipes.
      Each ingredient shows a per-station amount (station_qty). Compute the total to buy:
      - Multiply each ingredient's per-station amount by that class's station count.
      - Then sum the same ingredient across every class and recipe into one line.
      - Combine units sensibly (e.g. 3 T + 1/4 c -> about 1/2 c; round up to friendly
        shopping amounts). Use ASCII fractions like 1/2, 1/4, 2 1/2.
      - Ingredients with no amount ("Salt, to taste") go in to_taste as a deduped list of
        plain names (no "to taste" suffix), NOT in categories.
      - Organize the rest into common grocery sections in this order when present:
        Produce, Dairy and refrigerated, Meat and seafood, Pantry and dry goods, Other.
      - Merge ingredients that are clearly the same item (e.g. "Parmesan" and
        "Grated Parmesan"). Keep the clearest name.
      Do not invent ingredients that are not in the input.
    PROMPT

    def build_prompt(items)
      lines = items.map.with_index(1) do |it, idx|
        recipe_text = Array(it[:recipes]).flat_map do |r|
          Array(r["ingredients"]).map do |ing|
            amt = ing["station_qty"].presence || ing["qty"].to_s
            "    - #{amt} #{ing['item']}".rstrip
          end
        end.join("\n")
        "Class #{idx}: #{it[:class_name]} (#{it[:stations]} stations)\n#{recipe_text}"
      end
      "Build the grocery list for these classes:\n\n#{lines.join("\n\n")}"
    end

    def parse(response)
      raw = response.content&.first&.text.to_s
      json = raw[/\{.*\}/m]
      return nil if json.blank?
      parsed = JSON.parse(json)
      return nil unless parsed["categories"].is_a?(Array)
      parsed["to_taste"] ||= []
      parsed
    rescue JSON::ParserError
      nil
    end
  end
end
