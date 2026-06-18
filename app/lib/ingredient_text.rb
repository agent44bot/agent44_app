# Cleans punctuation artifacts in imported ingredient names. Recipe sites
# (especially WP Recipe Maker / RecipeTinEats JSON-LD) emit ingredient strings
# like "fresh ginger (, finely grated)", "lemongrass paste ((Note 2))", and
# "Japanese eggplants, (, small...)". The extractor keeps the source text, so
# these end up on the printed handout. This fixes the clearly-broken patterns
# only, deterministically, so it never touches real words.
module IngredientText
  def self.clean(text)
    s = text.to_s
    return s if s.strip.empty?

    s = s.gsub(/\(\s*,\s*/, "(")            # "(, finely grated)" -> "(finely grated)"
    s = s.gsub(/\(\(([^()]+)\)\)/, '(\1)')  # "((Note 2))"        -> "(Note 2)"
    s = s.gsub(/,\s*\(/, " (")              # "eggplants, (small" -> "eggplants (small"
    s = s.gsub(/\s+,/, ",")                 # " ,"                -> ","
    s = s.gsub(/\(\s+/, "(").gsub(/\s+\)/, ")") # trim spaces just inside parens
    s.gsub(/\s{2,}/, " ").strip
  end
end
