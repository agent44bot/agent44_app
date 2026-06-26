# Cleans punctuation artifacts in imported ingredient names. Recipe sites
# (especially WP Recipe Maker / RecipeTinEats JSON-LD) emit ingredient strings
# like "fresh ginger (, finely grated)", "lemongrass paste ((Note 2))", and
# "Japanese eggplants, (, small...)". The extractor keeps the source text, so
# these end up on the printed packet. This fixes the clearly-broken patterns
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

  # Sentence-cases an ingredient name for the packet house style (Lora's
  # "standardize ... capitalization" note): tone down SHOUTING by lowercasing
  # all-caps words ("KOSHER SALT" -> "kosher salt"), then capitalize the first
  # letter of the line. Mixed-case words (Dijon, McCormick, brand names) are
  # left alone, so proper nouns keep their capitals.
  def self.sentence_case(text)
    s = text.to_s.strip
    return s if s.empty?

    s = s.gsub(/\b\p{Lu}{2,}\b/) { |w| w.downcase } # ALL-CAPS word -> lowercase
    s.sub(/\p{L}/) { |c| c.upcase }                 # capitalize first letter
  end

  # Both passes in packet order: fix punctuation artifacts, then sentence-case.
  def self.normalize(text)
    sentence_case(clean(text))
  end
end
