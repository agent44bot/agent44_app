require "test_helper"
require "ostruct"

# ExtractRecipeJob runs recipe extraction off the web request. The AI is stubbed
# (never hits the Anthropic API); we assert the packet moves building -> ready
# (or failed) and that the stored source is cleared on success.
class ExtractRecipeJobTest < ActiveJob::TestCase
  EXTRACTED = [ {
    "title" => "Fresh Pasta",
    "ingredients" => [ { "qty" => "2 c", "station_qty" => "1 c", "item" => "Flour", "section" => nil } ],
    "directions"  => [ { "section" => nil, "steps" => [ "Mix and knead." ] } ]
  } ].freeze

  teardown { KitchenAi::RecipeExtractor.stub = nil }

  def stub_success
    KitchenAi::RecipeExtractor.stub = ->(messages:) {
      OpenStruct.new(content: [ OpenStruct.new(text: { "recipes" => EXTRACTED }.to_json) ],
                     usage: OpenStruct.new(input_tokens: 100, output_tokens: 200))
    }
  end

  def building_packet(title: "Chef's Table 7/10", source_text: "some recipe text")
    KitchenPacket.create!(title: title, status: "building", data: {}, source_text: source_text, source_kind: "text")
  end

  test "success fills recipes, marks ready, captures cost, clears the stored source" do
    stub_success
    packet = building_packet
    ExtractRecipeJob.perform_now(packet.id)
    packet.reload
    assert packet.ready?
    assert_equal "Fresh Pasta", packet.recipes.first["title"]
    assert packet.extract_cost_cents.to_i.positive?, "captures the extraction cost"
    assert_nil packet.source_text, "clears the consumed source"
    assert_nil packet.extract_error
  end

  test "titles the packet from the recipe when no class name was given" do
    stub_success
    packet = building_packet(title: KitchenPacket::BUILDING_TITLE)
    ExtractRecipeJob.perform_now(packet.id)
    assert_equal "Fresh Pasta", packet.reload.title
  end

  test "keeps a provided class name as the title" do
    stub_success
    packet = building_packet(title: "Chef's Table 7/10")
    ExtractRecipeJob.perform_now(packet.id)
    assert_equal "Chef's Table 7/10", packet.reload.title
  end

  test "failure marks the packet failed with the error message" do
    KitchenAi::RecipeExtractor.stub = ->(messages:) {
      OpenStruct.new(content: [ OpenStruct.new(text: "sorry, no recipe here") ],
                     usage: OpenStruct.new(input_tokens: 10, output_tokens: 10), stop_reason: "end_turn")
    }
    packet = building_packet
    ExtractRecipeJob.perform_now(packet.id)
    packet.reload
    assert packet.failed?
    assert_match(/could not find a recipe/i, packet.extract_error)
    assert packet.recipes.empty?
  end

  test "no-ops on a missing packet or one already processed" do
    stub_success
    ready = KitchenPacket.create!(title: "Done", status: "ready", data: { "recipes" => EXTRACTED })
    assert_nothing_raised { ExtractRecipeJob.perform_now(ready.id) } # not building: skipped
    assert_equal EXTRACTED, ready.reload.recipes
    assert_nothing_raised { ExtractRecipeJob.perform_now(999_999) } # deleted: skipped
  end
end
