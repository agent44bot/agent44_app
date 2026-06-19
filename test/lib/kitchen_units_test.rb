require "test_helper"

class KitchenUnitsTest < ActiveSupport::TestCase
  def assert_std(expected, input)
    assert_equal expected, KitchenUnits.standardize(input), "for #{input.inspect}"
  end

  test "Lora's house style: tablespoon -> T, teaspoon -> tsp, cup -> c" do
    assert_std "2 T",     "2 Tablespoons"
    assert_std "1 T",     "1 tablespoon"
    assert_std "3 tsp",   "3 teaspoons"
    assert_std "1 tsp",   "1 Teaspoon"
    assert_std "1/2 c",   "1/2 cup"
    assert_std "2 c",     "2 Cups"
  end

  test "common abbreviations fold in (with or without trailing period)" do
    assert_std "2 T",   "2 tbsp"
    assert_std "2 T",   "2 Tbsp."
    assert_std "2 T",   "2 tbs"
    assert_std "1 tsp", "1 tsp."
    assert_std "1 tsp", "1 TSP"
  end

  test "single-letter shorthand is case-sensitive (T stays, t -> tsp, C -> c)" do
    assert_std "1 T",   "1 T"      # already tablespoon
    assert_std "1 tsp", "1 t"      # lowercase t = teaspoon
    assert_std "1 c",   "1 C"      # capital C = cup
    assert_std "2 c",   "2 c"      # already lowercase cup
  end

  test "leaves unicode fractions, ranges, other units, and 'to taste' untouched" do
    assert_std "2½ c",        "2½ cups"
    assert_std "2-3 T",       "2-3 tablespoons"
    assert_std "8 oz",        "8 oz"
    assert_std "2 cloves",    "2 cloves"
    assert_std "1 lb",        "1 lb"
    assert_std "Salt, to taste", "Salt, to taste"
  end

  test "Lora's weight house style: grams/kg/oz/lb fold to short forms" do
    assert_std "200 g",  "200 grams"
    assert_std "1 g",    "1 gram"
    assert_std "50 g",   "50 gm"
    assert_std "50 g",   "50 gms"
    assert_std "1.5 kg", "1.5 Kilograms"
    assert_std "2 kg",   "2 KG"
    assert_std "8 oz",   "8 ounces"
    assert_std "1 oz",   "1 Ounce"
    assert_std "2 lb",   "2 pounds"
    assert_std "1 lb",   "1 Pound"
    assert_std "3 lb",   "3 lbs"
  end

  test "weight units already in short form stay put" do
    assert_std "8 oz",  "8 oz"
    assert_std "1 lb",  "1 lb"
    assert_std "200 g", "200 g"
    assert_std "2 kg",  "2 kg"
  end

  test "does not mangle words that merely contain a unit" do
    assert_std "cupcake liners", "cupcake liners"
    assert_std "buttercup",      "buttercup"
    assert_std "program notes",  "program notes"  # 'gram' inside 'program'
    assert_std "cozy",           "cozy"           # 'oz' inside 'cozy'
  end

  test "blank in, blank out" do
    assert_std "",  ""
    assert_std "",  nil
  end

  def assert_flour(grams, qty)
    assert_equal grams, KitchenUnits.flour_grams(qty), "for #{qty.inspect}"
  end

  test "flour_grams converts volume to grams (1 c ~ 120 g, rounded to 5)" do
    assert_flour 120, "1 c"
    assert_flour 240, "2 c"
    assert_flour 60,  "1/2 c"
    assert_flour 30,  "1/4 c"
    assert_flour 300, "2½ c"        # unicode fraction
    assert_flour 180, "1 1/2 c"     # mixed number
    assert_flour 15,  "2 T"         # 2 * 7.5
    assert_flour 5,   "2 tsp"       # 2 * 2.5
  end

  test "flour_grams uses the first number of a range" do
    assert_flour 240, "2-3 c"
  end

  test "flour_grams returns nil when it isn't a convertible volume" do
    assert_nil KitchenUnits.flour_grams("8 oz")     # already a weight
    assert_nil KitchenUnits.flour_grams("1 lb")
    assert_nil KitchenUnits.flour_grams("to taste")
    assert_nil KitchenUnits.flour_grams("")
    assert_nil KitchenUnits.flour_grams(nil)
  end
end
