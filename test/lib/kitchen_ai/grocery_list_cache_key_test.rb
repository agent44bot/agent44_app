require "test_helper"
require "ostruct"

# The grocery/pull-sheet cache key keys on the ingredient-bearing recipe data,
# NOT on equipment: equipment is per-station setup gear the pull sheet renders
# live and which has no bearing on the aggregation. Tying it into the key would
# re-bill Opus every time someone tweaks an equipment tag.
class GroceryListCacheKeyTest < ActiveSupport::TestCase
  def with_recipe(equipment:, recipes: [ { "title" => "Pasta" } ])
    [ {
      event: OpenStruct.new(url: "https://nyk/event/a"),
      tag: "A",
      stations: 6,
      packet: OpenStruct.new(data: { "recipes" => recipes, "equipment" => equipment })
    } ]
  end

  test "equipment changes do not change the cache key" do
    a = KitchenAi::GroceryList.cache_key(with_recipe(equipment: [ "Whisk" ]))
    b = KitchenAi::GroceryList.cache_key(with_recipe(equipment: [ "Whisk", "Colander" ]))
    assert_equal a, b, "adding equipment must not bust the aggregation cache (would re-bill Opus)"
  end

  test "recipe ingredient changes do change the cache key" do
    a = KitchenAi::GroceryList.cache_key(with_recipe(equipment: [], recipes: [ { "title" => "Pasta" } ]))
    b = KitchenAi::GroceryList.cache_key(with_recipe(equipment: [], recipes: [ { "title" => "Pasta", "x" => 1 } ]))
    refute_equal a, b, "a real recipe change should rebuild the list"
  end
end
