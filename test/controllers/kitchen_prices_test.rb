require "test_helper"

# The pantry page: view/edit/delete the latest observed price per ingredient.
class KitchenPricesTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "pantry-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(@user)
  end

  test "prices page lists the latest price per ingredient" do
    IngredientPrice.create!(canonical_name: "chicken breast", unit: "lb", unit_price_cents: 599, observed_on: Date.new(2026, 6, 1))
    IngredientPrice.create!(canonical_name: "chicken breast", unit: "lb", unit_price_cents: 699, observed_on: Date.new(2026, 6, 10))
    get nyk_prices_path
    assert_response :success
    assert_select "body", /chicken breast/i
    # Latest (6.99) shown, not the older 5.99.
    assert_match "6.99", response.body
  end

  test "update_price edits the dollar price and unit" do
    p = IngredientPrice.create!(canonical_name: "olive oil", unit: "each", unit_price_cents: 1299, observed_on: Date.current)
    patch nyk_price_path(p), params: { unit_price_dollars: "9.49", unit: "bottle" }
    assert_redirected_to nyk_prices_path
    p.reload
    assert_equal 949, p.unit_price_cents
    assert_equal "bottle", p.unit
  end

  test "destroy_price removes the row" do
    p = IngredientPrice.create!(canonical_name: "saffron", unit: "g", unit_price_cents: 5000, observed_on: Date.current)
    assert_difference -> { IngredientPrice.count }, -1 do
      delete nyk_price_path(p)
    end
    assert_redirected_to nyk_prices_path
  end
end
