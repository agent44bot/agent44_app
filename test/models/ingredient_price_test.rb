require "test_helper"

class IngredientPriceTest < ActiveSupport::TestCase
  test "recent_by_name returns the most recent price per canonical name" do
    IngredientPrice.create!(canonical_name: "chicken breast", unit: "lb", unit_price_cents: 599, observed_on: Date.new(2026, 6, 1))
    latest = IngredientPrice.create!(canonical_name: "chicken breast", unit: "lb", unit_price_cents: 699, observed_on: Date.new(2026, 6, 10))
    IngredientPrice.create!(canonical_name: "olive oil", unit: "each", unit_price_cents: 1299, observed_on: Date.new(2026, 6, 5))

    map = IngredientPrice.recent_by_name
    assert_equal latest.id, map["chicken breast"].id, "should keep the newest observation"
    assert_equal 1299, map["olive oil"].unit_price_cents
  end

  test "recent_by_name drops observations older than the window" do
    IngredientPrice.create!(canonical_name: "saffron", unit: "g", unit_price_cents: 5000, observed_on: 2.years.ago.to_date)
    assert_nil IngredientPrice.recent_by_name["saffron"]
  end
end
