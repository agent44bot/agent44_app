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

  test "equipment reads and writes the data list, preserving recipes" do
    h = make("Pasta")
    assert_equal [], h.equipment
    h.equipment = [ "Large stockpot", "Wooden spoon" ]
    h.save!
    assert_equal [ "Large stockpot", "Wooden spoon" ], h.reload.equipment
    assert_equal 1, h.recipes.size
  end

  test "hide_equipment drops a tag from the catalog for good, even if a recipe uses it" do
    h = make("Pasta")
    h.equipment = [ "Pasta machine" ]
    h.save!
    assert_includes KitchenHandout.equipment_catalog, "Pasta machine"
    assert_includes KitchenHandout.equipment_catalog, "Whisk" # a starter tag

    KitchenHandout.hide_equipment("Pasta machine")
    KitchenHandout.hide_equipment("whisk") # case-insensitive vs starter "Whisk"

    refute_includes KitchenHandout.equipment_catalog, "Pasta machine"
    refute_includes KitchenHandout.equipment_catalog.map(&:downcase), "whisk"
  end

  test "hide_equipment ignores blanks and de-dupes" do
    KitchenHandout.hide_equipment("Tongs")
    KitchenHandout.hide_equipment("tongs")
    KitchenHandout.hide_equipment("  ")
    assert_equal [ "Tongs" ], KitchenHandout.hidden_equipment
  end

  test "equipment_catalog merges the starter palette with used items, de-duped and sorted" do
    h = make("Pasta")
    h.equipment = [ "Pasta machine", "whisk" ] # 'whisk' duplicates starter 'Whisk'
    h.save!
    cat = KitchenHandout.equipment_catalog
    assert_includes cat, "Pasta machine"  # a used item appears
    assert_includes cat, "Cutting board"  # a starter item appears
    assert_equal 1, cat.count { |e| e.downcase == "whisk" }, "case-insensitive de-dupe"
    assert_equal cat.sort_by(&:downcase), cat, "sorted case-insensitively"
  end
end
