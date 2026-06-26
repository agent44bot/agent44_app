# House style for recipe-packet measurements (Lora's request): standardize the
# common volume and weight units so every printed packet reads the same way.
#
#   tablespoon -> T    teaspoon -> tsp    cup -> c
#   gram -> g    kilogram -> kg    ounce -> oz    pound -> lb
#
# Weight units only normalize the spelling/abbreviation; the numbers are never
# touched (no volume->weight conversion).
#
# Applied to the short qty / station_qty display strings only, never ingredient
# names or directions, so it can't mangle a word like "cupcake" or a step that
# happens to say "tablespoon".
module KitchenUnits
  def self.standardize(text)
    s = text.to_s
    return s if s.strip.empty?

    # Word/abbreviation forms first (most specific first). A trailing period
    # ("tbsp.") is consumed. Case-insensitive: "Tablespoon", "TBSP" all fold in.
    s = s.gsub(/\b(?:tablespoons?|tbsps?|tbs|tbl)\b\.?/i, "T")
    s = s.gsub(/\b(?:teaspoons?|tsps?)\b\.?/i, "tsp")
    s = s.gsub(/\bcups?\b\.?/i, "c")

    # Weight units: normalize spelled-out / variant abbreviations to short forms.
    # "kilograms" before "grams" so the longer unit wins. Numbers are untouched
    # (this is spelling normalization, not a volume->weight conversion).
    s = s.gsub(/\b(?:kilograms?|kgs?)\b\.?/i, "kg")
    s = s.gsub(/\b(?:grams?|gms?)\b\.?/i, "g")
    s = s.gsub(/\b(?:ounces?|ozs?)\b\.?/i, "oz")
    s = s.gsub(/\b(?:pounds?|lbs?)\b\.?/i, "lb")

    # Lone single-letter units. Recipe shorthand is case-sensitive: "T" is
    # already tablespoon (leave it), lowercase "t" is teaspoon, and "C" is cup.
    s = s.gsub(/\bt\b/, "tsp")
    s = s.gsub(/\bC\b/, "c")

    s.gsub(/\s{2,}/, " ").strip
  end

  # Approximate grams of all-purpose flour per standardized volume unit. Flour
  # by volume is imprecise, so the kitchen weighs it (Lora's "add grams when
  # ingredient is flour"). King Arthur's reference: 1 cup ~ 120 g.
  FLOUR_GRAMS_PER_UNIT = { "c" => 120.0, "T" => 7.5, "tsp" => 2.5 }.freeze

  # Unicode vulgar fractions -> decimal, for parsing a leading quantity.
  VULGAR_FRACTIONS = {
    "½" => 0.5, "⅓" => 1.0 / 3, "⅔" => 2.0 / 3, "¼" => 0.25, "¾" => 0.75,
    "⅕" => 0.2, "⅖" => 0.4, "⅗" => 0.6, "⅘" => 0.8, "⅙" => 1.0 / 6,
    "⅚" => 5.0 / 6, "⅛" => 0.125, "⅜" => 0.375, "⅝" => 0.625, "⅞" => 0.875
  }.freeze

  # Grams of all-purpose flour for a standardized qty string ("2½ c", "1/2 c",
  # "3 T"), rounded to the nearest 5 g, or nil when it isn't a convertible
  # volume. Ranges ("2-3 c") use the first number. Numbers without a c/T/tsp
  # unit (already a weight, "to taste", etc.) return nil.
  def self.flour_grams(qty_text)
    s = qty_text.to_s.strip
    return nil if s.empty?

    unit = s[/\b(c|T|tsp)\b/, 1]
    grams_per = unit && FLOUR_GRAMS_PER_UNIT[unit]
    return nil unless grams_per

    amount = leading_amount(s)
    return nil unless amount

    (amount * grams_per / 5.0).round * 5
  end

  # Parse the leading numeric amount of a qty string: whole, decimal,
  # "a b/c" mixed, "b/c" fraction, or "N½" / "½" unicode. Returns a Float or nil.
  def self.leading_amount(text)
    s = text.to_s.strip
    # Split a number butted against a unicode fraction: "2½" -> "2 ½".
    s = s.gsub(/(\d)([#{VULGAR_FRACTIONS.keys.join}])/, '\1 \2')

    if (m = s.match(/\A(\d+)\s+(\d+)\/(\d+)/))            # "2 1/2"
      m[1].to_f + m[2].to_f / m[3].to_f
    elsif (m = s.match(/\A(\d+)\/(\d+)/))                 # "1/2"
      m[1].to_f / m[2].to_f
    elsif (m = s.match(/\A(\d+)\s+([#{VULGAR_FRACTIONS.keys.join}])/)) # "2 ½"
      m[1].to_f + VULGAR_FRACTIONS[m[2]]
    elsif (m = s.match(/\A([#{VULGAR_FRACTIONS.keys.join}])/))         # "½"
      VULGAR_FRACTIONS[m[1]]
    elsif (m = s.match(/\A(\d+(?:\.\d+)?)/))             # "2" or "2.5"
      m[1].to_f
    end
  end
end
