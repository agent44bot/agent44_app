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
  # Short all-caps words are abbreviations, not shouting: "AP flour", "EVOO",
  # "DOP tomatoes", "IPA". Lowercasing those read as a typo on the handout
  # ("Ap flour"), so only longer words are toned down -- unless the whole line
  # is caps ("KOSHER SALT"), which is shouting whatever the word lengths are.
  ABBREV_MAX = 4

  def self.sentence_case(text)
    s = text.to_s.strip
    return s if s.empty?

    s = if shouting?(s)
      s.downcase
    else
      s.gsub(/\b\p{Lu}{#{ABBREV_MAX + 1},}\b/) { |w| w.downcase }
    end
    s.sub(/\p{L}/) { |c| c.upcase } # capitalize first letter
  end

  # The whole line is upper case (it has letters, and none of them are lower).
  def self.shouting?(text)
    text.match?(/\p{Lu}/) && !text.match?(/\p{Ll}/)
  end

  # Both passes in packet order: fix punctuation artifacts, then sentence-case.
  def self.normalize(text)
    sentence_case(clean(text))
  end
end
