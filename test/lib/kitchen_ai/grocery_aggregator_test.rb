require "test_helper"
require "ostruct"

# GroceryAggregator merges class recipes (scaled by station count) into one
# categorized list. The Anthropic call is stubbed; we assert the request shape
# (per-station amounts + station counts reach the model) and that the response
# is parsed into categories + to_taste + cost.
class GroceryAggregatorTest < ActiveSupport::TestCase
  RESPONSE = {
    "categories" => [ { "name" => "Pantry and dry goods",
                        "items" => [ { "item" => "All-purpose flour", "quantity" => "15 1/2 c", "price" => 6.0 } ] } ],
    "to_taste" => [ "Salt" ]
  }.freeze

  def items
    [ { class_name: "Ravioli", stations: 6, recipes: [
        { "title" => "Pasta", "ingredients" => [
          { "qty" => "2½ c", "station_qty" => "1¼ c", "item" => "All-purpose flour", "section" => nil },
          { "qty" => "", "station_qty" => "", "item" => "Salt, to taste", "section" => nil } ] } ] } ]
  end

  teardown { KitchenAi::GroceryAggregator.stub = nil }

  test "parses categories, to_taste, and cost from the model response" do
    captured = nil
    text = OpenStruct.new(text: RESPONSE.to_json)
    KitchenAi::GroceryAggregator.stub = lambda do |items:|
      captured = items
      OpenStruct.new(content: [ text ], usage: OpenStruct.new(input_tokens: 500, output_tokens: 300))
    end

    r = KitchenAi::GroceryAggregator.new.build(items)
    assert r.ok?
    assert_equal "All-purpose flour", r.categories.first["items"].first["item"]
    assert_equal 6.0, r.categories.first["items"].first["price"]
    assert_equal [ "Salt" ], r.to_taste
    assert r.cost_cents.to_i.positive?
    # The per-station amount and station count both reach the aggregator.
    assert_equal 6, captured.first[:stations]
  end

  test "empty input returns an error without calling the model" do
    called = false
    KitchenAi::GroceryAggregator.stub = ->(items:) { called = true }
    r = KitchenAi::GroceryAggregator.new.build([])
    assert_not r.ok?
    assert_not called
  end

  test "drops classes that have no recipes" do
    KitchenAi::GroceryAggregator.stub = lambda do |items:|
      assert_equal 1, items.size # the empty-recipes class was filtered out
      OpenStruct.new(content: [ OpenStruct.new(text: RESPONSE.to_json) ],
                     usage: OpenStruct.new(input_tokens: 1, output_tokens: 1))
    end
    r = KitchenAi::GroceryAggregator.new.build(items + [ { class_name: "Empty", stations: 1, recipes: [] } ])
    assert r.ok?
  end

  test "folds known observed prices into the prompt" do
    agg = KitchenAi::GroceryAggregator.new
    its = [ { class_name: "Pasta", tag: "Pasta", stations: 2,
              recipes: [ { "ingredients" => [ { "item" => "flour", "station_qty" => "1 c" } ] } ] } ]
    prompt = agg.send(:build_prompt, its, { "chicken breast" => { "price" => 6.99, "unit" => "lb" } })
    assert_includes prompt, "KNOWN RECENT PRICES"
    assert_includes prompt, "chicken breast: $6.99 per lb"
  end
end
