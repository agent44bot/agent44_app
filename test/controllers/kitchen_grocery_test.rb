require "test_helper"
require "ostruct"

# The /nykitchen/grocery page: gathers in-range classes with recipes, scales by
# station count, and renders the aggregated list. The aggregator is stubbed.
class KitchenGroceryTest < ActionDispatch::IntegrationTest
  RECIPE = [ { "title" => "Pasta",
               "ingredients" => [ { "qty" => "2½ c", "station_qty" => "1¼ c", "item" => "Flour", "section" => nil } ],
               "directions" => [] } ].freeze
  AGG = { "categories" => [ { "name" => "Pantry and dry goods",
                              "items" => [ { "item" => "Flour", "quantity" => "7 1/2 c" } ] } ],
          "to_taste" => [ "Salt" ] }.freeze

  setup do
    @user = User.create!(email_address: "groc-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(@user)
    @snap = KitchenSnapshot.create!(taken_on: Date.current)
    KitchenAi::GroceryAggregator.stub = lambda do |items:|
      @captured = items
      OpenStruct.new(content: [ OpenStruct.new(text: AGG.to_json) ],
                     usage: OpenStruct.new(input_tokens: 10, output_tokens: 10))
    end
  end

  teardown { KitchenAi::GroceryAggregator.stub = nil }

  def add_class(name, slug, days_out, booked:, cap: 24, recipe: true)
    url = "https://nykitchen.com/event/#{slug}/"
    @snap.kitchen_events.create!(name: name, url: url, start_at: days_out.days.from_now.change(hour: 18),
                                 availability: "InStock", capacity: cap, spots_left: cap - booked)
    if recipe
      h = KitchenHandout.create!(title: name, data: { "recipes" => RECIPE })
      h.attach_to!(url)
    end
    url
  end

  test "renders the aggregated list for in-range classes with recipes" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path
    assert_response :success
    assert_match "NY Kitchen Grocery List", response.body
    assert_match "Flour", response.body
    assert_match "Salt", response.body # to_taste
  end

  test "scales by stations: 12 booked => 6 stations" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path
    assert_equal 6, @captured.first[:stations]
  end

  test "flags in-range classes that have no recipe and excludes them" do
    add_class("Has Recipe", "groc-has", 1, booked: 8)
    add_class("No Recipe", "groc-no", 1, booked: 4, recipe: false)
    get nyk_grocery_path
    assert_response :success
    assert_match "No Recipe", response.body
    assert_match "no recipe", response.body
    assert_equal 1, @captured.size # only the class with a recipe goes to the aggregator
  end

  test "empty when no in-range class has a recipe" do
    add_class("Future No Recipe", "groc-fut", 1, booked: 4, recipe: false)
    get nyk_grocery_path
    assert_response :success
    assert_match "No classes in this range have a recipe", response.body
  end

  test "includes sold-out classes (the fullest ones to shop for)" do
    url = "https://nykitchen.com/event/groc-soldout/"
    @snap.kitchen_events.create!(name: "Sold Out Dinner", url: url, start_at: 1.day.from_now.change(hour: 18),
                                 availability: "SoldOut", capacity: 20, spots_left: 0)
    h = KitchenHandout.create!(title: "Sold Out Dinner", data: { "recipes" => RECIPE })
    h.attach_to!(url)
    get nyk_grocery_path
    assert_response :success
    assert_match "NY Kitchen Grocery List", response.body
    assert_equal 1, @captured.size
    assert_equal 10, @captured.first[:stations] # 20 booked => 10 stations
  end

  test "days param widens the window" do
    add_class("Far Out", "groc-far", 12, booked: 6)
    get nyk_grocery_path # default weekend window excludes day +12
    assert_match "No classes in this range have a recipe", response.body
    get nyk_grocery_path(days: 14)
    assert_match "NY Kitchen Grocery List", response.body
  end
end
