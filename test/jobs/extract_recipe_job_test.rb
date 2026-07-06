require "test_helper"
require "ostruct"

# ExtractRecipeJob builds a packet in the background, walking build_stage
# reading -> recipes -> equipment -> ready. The AI is stubbed (never hits the
# Anthropic API); we assert the stages, the stored recipes + equipment, and the
# failure path.
class ExtractRecipeJobTest < ActiveJob::TestCase
  RECIPES = [ {
    "title" => "Fresh Pasta",
    "ingredients" => [ { "qty" => "2 c", "station_qty" => "1 c", "item" => "Flour", "section" => nil } ],
    "directions"  => [ { "section" => nil, "steps" => [ "Mix and knead." ] } ]
  } ].freeze

  teardown { KitchenAi::RecipeExtractor.stub = nil }

  # The extractor makes two calls (recipes, then equipment). The stub answers
  # both: a recipes payload, then an equipment payload, in that order.
  def stub_extractor(recipes: RECIPES, equipment: %w[Whisk Saucepan])
    calls = 0
    KitchenAi::RecipeExtractor.stub = lambda do |messages:|
      calls += 1
      body = calls == 1 ? { "recipes" => recipes } : { "equipment" => equipment }
      OpenStruct.new(content: [ OpenStruct.new(text: body.to_json) ],
                     usage: OpenStruct.new(input_tokens: 50, output_tokens: 50))
    end
  end

  def building_packet(title: "Chef's Table 7/10", source_text: "some recipe text")
    KitchenPacket.create!(title: title, status: "building", build_stage: "queued",
                          data: {}, source_text: source_text, source_kind: "text")
  end

  test "success fills recipes + equipment, ends ready at stage ready, clears source" do
    stub_extractor
    packet = building_packet
    ExtractRecipeJob.perform_now(packet.id)
    packet.reload
    assert packet.ready?
    assert_equal "ready", packet.build_stage
    assert_equal "Fresh Pasta", packet.recipes.first["title"]
    assert_equal %w[Whisk Saucepan], packet.equipment
    assert packet.extract_cost_cents # captured from the recipe call
    assert_nil packet.source_text
  end

  test "titles the packet from the recipe when no class name was given" do
    stub_extractor
    packet = building_packet(title: KitchenPacket::BUILDING_TITLE)
    ExtractRecipeJob.perform_now(packet.id)
    assert_equal "Fresh Pasta", packet.reload.title
  end

  test "a failed recipe extraction marks the packet failed and clears the stage" do
    KitchenAi::RecipeExtractor.stub = lambda do |messages:|
      OpenStruct.new(content: [ OpenStruct.new(text: "not a recipe") ],
                     usage: OpenStruct.new(input_tokens: 10, output_tokens: 10), stop_reason: "end_turn")
    end
    packet = building_packet
    ExtractRecipeJob.perform_now(packet.id)
    packet.reload
    assert packet.failed?
    assert_nil packet.build_stage
    assert_match(/could not find a recipe/i, packet.extract_error)
  end

  test "an equipment miss still leaves a ready packet with the recipes" do
    stub_extractor(equipment: []) # empty equipment payload
    packet = building_packet
    ExtractRecipeJob.perform_now(packet.id)
    packet.reload
    assert packet.ready?
    assert_equal 1, packet.recipes.size
    assert_empty packet.equipment
  end

  test "no-ops on a missing or already-finished packet" do
    stub_extractor
    ready = KitchenPacket.create!(title: "Done", status: "ready", data: { "recipes" => RECIPES })
    assert_nothing_raised { ExtractRecipeJob.perform_now(ready.id) }
    assert_nothing_raised { ExtractRecipeJob.perform_now(999_999) }
  end

  test "runs on its own low-concurrency queue" do
    assert_equal "extraction", ExtractRecipeJob.new.queue_name
  end
end
