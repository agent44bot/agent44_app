require "test_helper"

class KitchenPacketTest < ActiveSupport::TestCase
  RECIPES = [
    {
      "title" => "Fresh Pasta",
      "ingredients" => [ { "qty" => "2½ c", "station_qty" => "1¼ c", "item" => "All-purpose flour", "section" => nil } ],
      "directions" => [ { "section" => nil, "steps" => [ "Mix." ] } ]
    }
  ].freeze

  def make(title, ingredient = "All-purpose flour")
    KitchenPacket.create!(title: title, data: { "recipes" => [
      { "title" => title,
        "ingredients" => [ { "qty" => "1 c", "station_qty" => "1/2 c", "item" => ingredient, "section" => nil } ],
        "directions" => [ { "section" => nil, "steps" => [ "Mix." ] } ] }
    ] })
  end

  test "search matches the title" do
    pasta = make("Fresh Pasta")
    make("Sourdough Basics")
    assert_equal [ pasta ], KitchenPacket.search("pasta").to_a
  end

  test "search matches an ingredient inside the recipe data" do
    pasta = make("Fresh Pasta", "All-purpose flour")
    make("Sourdough Basics", "Rye")
    assert_equal [ pasta ], KitchenPacket.search("all-purpose").to_a
  end

  test "blank search returns everything" do
    make("Fresh Pasta")
    make("Sourdough Basics")
    assert_equal 2, KitchenPacket.search("").count
    assert_equal 2, KitchenPacket.search(nil).count
  end

  test "search escapes LIKE wildcards so they match literally" do
    make("Fresh Pasta")
    assert_equal 0, KitchenPacket.search("%").count
  end

  test "search_text flattens title, ingredients, and steps, lowercased" do
    packet = KitchenPacket.create!(title: "Fresh Pasta", data: { "recipes" => [
      { "title" => "Cherry Sauce",
        "ingredients" => [ { "qty" => "2 c", "station_qty" => "1 c", "item" => "Cherry tomatoes", "section" => nil } ],
        "directions" => [ { "section" => nil, "steps" => [ "Simmer the tomatoes." ] } ] }
    ] })
    text = packet.search_text
    assert_includes text, "fresh pasta"
    assert_includes text, "cherry sauce"
    assert_includes text, "cherry tomatoes"
    assert_includes text, "simmer the tomatoes."
    assert_equal text, text.downcase
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
    assert_includes KitchenPacket.equipment_catalog, "Pasta machine"
    assert_includes KitchenPacket.equipment_catalog, "Whisk" # a starter tag

    KitchenPacket.hide_equipment("Pasta machine")
    KitchenPacket.hide_equipment("whisk") # case-insensitive vs starter "Whisk"

    refute_includes KitchenPacket.equipment_catalog, "Pasta machine"
    refute_includes KitchenPacket.equipment_catalog.map(&:downcase), "whisk"
  end

  test "hide_equipment ignores blanks and de-dupes" do
    KitchenPacket.hide_equipment("Tongs")
    KitchenPacket.hide_equipment("tongs")
    KitchenPacket.hide_equipment("  ")
    assert_equal [ "Tongs" ], KitchenPacket.hidden_equipment
  end

  test "equipment_catalog merges the starter palette with used items, de-duped and sorted" do
    h = make("Pasta")
    h.equipment = [ "Pasta machine", "whisk" ] # 'whisk' duplicates starter 'Whisk'
    h.save!
    cat = KitchenPacket.equipment_catalog
    assert_includes cat, "Pasta machine"  # a used item appears
    assert_includes cat, "Cutting board"  # a starter item appears
    assert_equal 1, cat.count { |e| e.downcase == "whisk" }, "case-insensitive de-dupe"
    assert_equal cat.sort_by(&:downcase), cat, "sorted case-insensitively"
  end
end
