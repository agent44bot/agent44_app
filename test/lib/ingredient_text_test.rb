require "test_helper"

class IngredientTextTest < ActiveSupport::TestCase
  def assert_clean(expected, input)
    assert_equal expected, IngredientText.clean(input), "for #{input.inspect}"
  end

  test "drops a comma right after an opening paren" do
    assert_clean "fresh ginger (finely grated)", "fresh ginger (, finely grated)"
    assert_clean "snow peas (small, trimmed)",   "snow peas (, small, trimmed)"
    assert_clean "Juice of 1/2 lime (to taste)", "Juice of 1/2 lime (, to taste)"
    assert_clean "Green or red chillies slices (optional)", "Green or red chillies slices (, optional)"
  end

  test "collapses doubled parens around a note" do
    assert_clean "lemongrass paste (Note 2)", "lemongrass paste ((Note 2))"
    assert_clean "Thai basil leaves (Note 8)", "Thai basil leaves ((Note 8))"
  end

  test "keeps legitimately nested parens (note inside a descriptor)" do
    assert_clean "coconut milk (full fat (Note 4))", "coconut milk (, full fat (Note 4))"
    assert_clean "kaffir lime leaves (torn in half (Note 5))", "kaffir lime leaves (, torn in half (Note 5))"
    assert_clean "chicken thigh (skinless boneless, sliced (Note 6))", "chicken thigh (, skinless boneless, sliced (Note 6))"
  end

  test "removes a stray comma right before a note" do
    assert_clean %(Japanese eggplants (small, 1cm / 2/5" slices (Note 7))),
                 %(Japanese eggplants, (, small, 1cm / 2/5" slices (Note 7)))
  end

  test "leaves clean text untouched" do
    assert_clean "chicken or vegetable broth, low sodium", "chicken or vegetable broth, low sodium"
    assert_clean "All-purpose flour", "All-purpose flour"
    assert_clean "fish sauce *", "fish sauce *"
    assert_clean "Steamed jasmine rice", "Steamed jasmine rice"
  end

  test "blank in, blank out" do
    assert_clean "", ""
    assert_clean "", nil
  end

  def assert_cased(expected, input)
    assert_equal expected, IngredientText.sentence_case(input), "for #{input.inspect}"
  end

  test "sentence case: capitalizes the first letter of the line" do
    assert_cased "Olive oil",                  "olive oil"
    assert_cased "All-purpose flour, sifted",  "all-purpose flour, sifted"
  end

  test "sentence case: tones down ALL-CAPS words" do
    assert_cased "Kosher salt",        "KOSHER SALT"
    assert_cased "Smoked paprika",     "smoked PAPRIKA"
  end

  test "sentence case: keeps mixed-case proper nouns and brands" do
    assert_cased "Dijon mustard",      "Dijon mustard"
    assert_cased "Parmesan, grated",   "Parmesan, grated"
    assert_cased "McCormick vanilla",  "McCormick vanilla"
  end

  test "sentence case: capitalizes first letter past a leading paren or symbol" do
    assert_cased "(Optional) garnish", "(optional) garnish"
    assert_cased "*Fish sauce",        "*fish sauce"
  end

  test "sentence case: blank in, blank out" do
    assert_cased "", ""
    assert_cased "", nil
  end

  test "normalize runs cleanup then sentence case" do
    assert_equal "Fresh ginger (finely grated)",
                 IngredientText.normalize("fresh ginger (, finely grated)")
    assert_equal "Kosher salt", IngredientText.normalize("KOSHER SALT")
  end
end
