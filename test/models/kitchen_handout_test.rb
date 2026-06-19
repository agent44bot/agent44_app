require "test_helper"

class KitchenHandoutTest < ActiveSupport::TestCase
  RECIPES = [
    {
      "title" => "Fresh Pasta",
      "ingredients" => [ { "qty" => "2½ c", "station_qty" => "1¼ c", "item" => "All-purpose flour", "section" => nil } ],
      "directions" => [ { "section" => nil, "steps" => [ "Mix." ] } ]
    }
  ].freeze

  def make(title, ingredient = "All-purpose flour")
    KitchenHandout.create!(title: title, data: { "recipes" => [
      { "title" => title,
        "ingredients" => [ { "qty" => "1 c", "station_qty" => "1/2 c", "item" => ingredient, "section" => nil } ],
        "directions" => [ { "section" => nil, "steps" => [ "Mix." ] } ] }
    ] })
  end

  test "search matches the title" do
    pasta = make("Fresh Pasta")
    make("Sourdough Basics")
    assert_equal [ pasta ], KitchenHandout.search("pasta").to_a
  end

  test "search matches an ingredient inside the recipe data" do
    pasta = make("Fresh Pasta", "All-purpose flour")
    make("Sourdough Basics", "Rye")
    assert_equal [ pasta ], KitchenHandout.search("all-purpose").to_a
  end

  test "blank search returns everything" do
    make("Fresh Pasta")
    make("Sourdough Basics")
    assert_equal 2, KitchenHandout.search("").count
    assert_equal 2, KitchenHandout.search(nil).count
  end

  test "search escapes LIKE wildcards so they match literally" do
    make("Fresh Pasta")
    assert_equal 0, KitchenHandout.search("%").count
  end
end
