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

  test "does not mangle words that merely contain a unit" do
    assert_std "cupcake liners", "cupcake liners"
    assert_std "buttercup",      "buttercup"
  end

  test "blank in, blank out" do
    assert_std "",  ""
    assert_std "",  nil
  end
end
