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

  # ----- build state (background extraction + navbar bar) -----

  test "a building packet is valid with no recipes yet" do
    p = KitchenPacket.new(title: "Chef's Table", status: "building", build_stage: "recipes", data: {})
    assert p.valid?, p.errors.full_messages.to_sentence
    assert p.building?
  end

  test "a ready packet must carry well-formed recipes; a failed one need not" do
    assert_not KitchenPacket.new(title: "x", status: "ready", data: {}).valid?
    assert KitchenPacket.new(title: "x", status: "failed", data: {}, extract_error: "boom").valid?
  end

  test "status must be one of the build statuses" do
    p = KitchenPacket.new(title: "x", status: "weird", data: { "recipes" => RECIPES })
    assert_not p.valid?
    assert p.errors[:status].any?
  end

  test "a normally-created packet defaults to ready" do
    assert make("Pasta").ready?
  end

  test "active_builds returns building packets and ones finished in the last few minutes" do
    building = KitchenPacket.create!(title: "Building", status: "building", build_stage: "recipes", data: {})
    just_done = make("Just Done"); just_done.update_columns(status: "ready", build_stage: "ready", updated_at: 1.minute.ago)
    make("Old Ready") # a normal ready packet, build_stage nil -> excluded
    stale = make("Stale"); stale.update_columns(status: "ready", build_stage: "ready", updated_at: 10.minutes.ago)

    ids = KitchenPacket.active_builds.pluck(:id)
    assert_includes ids, building.id
    assert_includes ids, just_done.id
    assert_not_includes ids, stale.id, "past the recent window"
  end
end
