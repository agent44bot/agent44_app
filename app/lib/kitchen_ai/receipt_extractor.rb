# Reads a photographed (or PDF) grocery receipt with Opus vision and returns
# the store, total, and normalized line items, so each item becomes an
# IngredientPrice the grocery estimator can reuse. Normalization is the point:
# "BNLS CHKN BRST" on the receipt becomes "chicken breast" so it matches the
# name a recipe uses.
#
# Stateless; mirrors KitchenAi::RecipeExtractor (class-level stub for tests,
# every response logged through AiCallLogger).
module KitchenAi
  class ReceiptExtractor
    MODEL      = "claude-opus-4-8"
    SOURCE     = "nyk_receipt_extract"
    MAX_TOKENS = 4000

    Result = Struct.new(:ok?, :store, :total_cents, :items, :error, :cost_cents, keyword_init: true)

    class << self
      attr_accessor :stub
    end

    def initialize(user: nil)
      @user = user
    end

    # image_bytes: raw file bytes. media_type: "image/jpeg", "image/png",
    # "image/webp", or "application/pdf". known_names: existing canonical
    # ingredient names to match new lines against (keeps the vocabulary stable).
    def extract(image_bytes:, media_type:, known_names: [])
      return Result.new(ok?: false, error: "No receipt file.") if image_bytes.blank?

      response =
        if self.class.stub
          self.class.stub.call(image_bytes: image_bytes, media_type: media_type, known_names: known_names)
        else
          api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
          return Result.new(ok?: false, error: "ANTHROPIC_API_KEY not set") if api_key.blank?
          Anthropic::Client.new(api_key: api_key).messages.create(
            model:      MODEL,
            max_tokens: MAX_TOKENS,
            system:     SYSTEM_PROMPT,
            messages:   [ { role: "user", content: build_content(image_bytes: image_bytes, media_type: media_type, known_names: known_names) } ]
          )
        end

      log = AiCallLogger.log!(response, model: MODEL, source: SOURCE, user: @user)
      parsed = parse(response)
      return Result.new(ok?: false, error: "Could not read that receipt. Try a clearer photo.") if parsed.nil?

      Result.new(ok?: true, store: parsed[:store], total_cents: parsed[:total_cents],
                 items: parsed[:items], cost_cents: log&.cost_cents&.round)
    rescue Anthropic::Errors::APIError => e
      Result.new(ok?: false, error: "Anthropic: #{e.message}")
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    private

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You read a photographed or scanned grocery store receipt and return its line items as JSON.

      Reply with ONLY a JSON object, no prose, no code fences:
      {"store": "Wegmans",
       "total": 214.30,
       "items": [{"raw_label": "BNLS CHKN BRST", "canonical_name": "chicken breast",
                  "quantity": 2.10, "unit": "lb", "unit_price": 6.99}]}

      Rules:
      - store: the store name if printed, else null.
      - total: the final amount paid in dollars as a plain number. Look for the
        largest summary line labelled TOTAL, BALANCE, BALANCE DUE, or AMOUNT DUE
        (not SUBTOTAL). Use null only if no total is printed at all.
      - One item per purchased PRODUCT line. Skip every non-product line:
        subtotals, totals, balance/amount due, tax, store/bag fees, coupons,
        discounts, savings, loyalty, change/tender, and BOTTLE OR CAN DEPOSITS.
      - raw_label: the line text exactly as printed on the receipt.
      - canonical_name: a clean, lower-case, generic ingredient name a recipe
        would use ("chicken breast", "romaine lettuce", "olive oil", "kosher
        salt"). Expand register abbreviations. Drop brand names and sizes.
      - quantity and unit: how much that line bought. unit is "lb", "oz", "each",
        "dozen", "gal", "qt", etc. If the line is a single packaged item, use
        quantity 1 and unit "each".
      - unit_price: price in dollars for ONE unit (line total divided by quantity),
        as a plain number.
      - If a list of KNOWN INGREDIENT NAMES is given, reuse the exact matching
        name for canonical_name when a line clearly refers to the same thing, so
        the vocabulary stays consistent. Otherwise pick a clean new name.
      - Do not invent lines that are not on the receipt.
    PROMPT

    def build_content(image_bytes:, media_type:, known_names:)
      data  = Base64.strict_encode64(image_bytes)
      block =
        if media_type.to_s == "application/pdf"
          { type: "document", source: { type: "base64", media_type: "application/pdf", data: data } }
        else
          { type: "image", source: { type: "base64", media_type: media_type.presence || "image/jpeg", data: data } }
        end
      prompt = "Read this grocery receipt."
      if known_names.present?
        prompt += "\n\nKNOWN INGREDIENT NAMES (reuse an exact match when a line is the same item):\n" \
                  "#{known_names.first(200).map { |n| "- #{n}" }.join("\n")}"
      end
      [ block, { type: "text", text: prompt } ]
    end

    def parse(response)
      raw  = response.content&.first&.text.to_s
      json = raw[/\{.*\}/m]
      return nil if json.blank?
      parsed = JSON.parse(json)
      items  = Array(parsed["items"]).filter_map { |i| normalize_item(i) }
      return nil if items.empty? && parsed["total"].blank?
      { store: parsed["store"].presence, total_cents: dollars_to_cents(parsed["total"]), items: items }
    rescue JSON::ParserError
      nil
    end

    # Non-product lines the model sometimes lists as items anyway (a bottle
    # deposit, tax, a fee). Drop them so they never become a "price".
    SKIP_LINE = /\b(deposit|btl|bottle\s*ret|tax|subtotal|total|balance|amount\s*due|coupon|discount|savings|loyalty|tender|change\s*due|bag\s*fee)\b/i

    def normalize_item(item)
      return nil unless item.is_a?(Hash)
      name = item["canonical_name"].to_s.strip.downcase
      raw  = item["raw_label"].to_s
      cents = dollars_to_cents(item["unit_price"])
      return nil if name.blank? || cents.nil?
      return nil if SKIP_LINE.match?(name) || SKIP_LINE.match?(raw)
      { canonical_name: name, raw_label: raw.strip.presence,
        unit: item["unit"].to_s.strip.presence, quantity: numeric(item["quantity"]),
        unit_price_cents: cents }
    end

    def dollars_to_cents(value)
      return nil if value.nil?
      n = numeric(value)
      n.nil? ? nil : (n * 100).round
    end

    def numeric(value)
      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
