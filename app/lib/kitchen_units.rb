# House style for recipe-handout measurements (Lora's request): standardize the
# common volume units so every printed packet reads the same way.
#
#   tablespoon -> T    teaspoon -> tsp    cup -> c
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

    # Lone single-letter units. Recipe shorthand is case-sensitive: "T" is
    # already tablespoon (leave it), lowercase "t" is teaspoon, and "C" is cup.
    s = s.gsub(/\bt\b/, "tsp")
    s = s.gsub(/\bC\b/, "c")

    s.gsub(/\s{2,}/, " ").strip
  end
end
