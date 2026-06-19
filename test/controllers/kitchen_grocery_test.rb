require "test_helper"
require "ostruct"

# The /nykitchen/grocery page: a fast shell + a lazy turbo frame that gathers
# in-range classes with recipes, scales by station count, tags each item with
# its classes, and renders the aggregated list. The aggregator is stubbed; the
# heavy content is only rendered on a turbo-frame request.
class KitchenGroceryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  RECIPE = [ { "title" => "Pasta",
               "ingredients" => [ { "qty" => "2½ c", "station_qty" => "1¼ c", "item" => "Flour", "section" => nil } ],
               "directions" => [] } ].freeze
  AGG = { "categories" => [ { "name" => "Pantry and dry goods",
                              "items" => [ { "item" => "Flour", "quantity" => "7 1/2 c", "price" => 4.50, "classes" => [ "Ravioli" ] } ] } ],
          "to_taste" => [ "Salt" ] }.freeze
  FRAME = { "Turbo-Frame" => "grocery_list" }.freeze

  setup do
    @user = User.create!(email_address: "groc-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(@user)
    @snap = KitchenSnapshot.create!(taken_on: Date.current)
    @agg_calls = 0
    KitchenAi::GroceryAggregator.stub = lambda do |items:|
      @agg_calls += 1
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

  test "the page shell loads fast with a spinner and does not build the list" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path # no Turbo-Frame header
    assert_response :success
    assert_match "Building your grocery list", response.body
    assert_no_match "NY Kitchen Grocery List", response.body
    assert_equal 0, @agg_calls, "shell must not call the aggregator"
  end

  test "the frame renders the aggregated list with item class tags" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path, headers: FRAME
    assert_response :success
    assert_match "NY Kitchen Grocery List", response.body
    assert_match "Flour", response.body
    assert_match "Salt", response.body         # to_taste
    assert_match "Ravioli", response.body      # class tag chip
  end

  test "the grocery list standardizes measurement units (T / tsp / c)" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    KitchenAi::GroceryAggregator.stub = lambda do |items:|
      agg = { "categories" => [ { "name" => "Pantry and dry goods", "items" => [
        { "item" => "Olive oil", "quantity" => "2 Tablespoons", "price" => 1.0, "classes" => [ "Ravioli" ] },
        { "item" => "Milk",      "quantity" => "1/2 cup",       "price" => 1.0, "classes" => [ "Ravioli" ] }
      ] } ], "to_taste" => [] }
      OpenStruct.new(content: [ OpenStruct.new(text: agg.to_json) ],
                     usage: OpenStruct.new(input_tokens: 10, output_tokens: 10))
    end
    get nyk_grocery_path, headers: FRAME
    assert_response :success
    assert_match "2 T", response.body
    assert_match "1/2 c", response.body
    assert_no_match(/2 Tablespoons/, response.body)
    assert_no_match(%r{1/2 cup}, response.body)
  end

  test "shows per-item price and an estimated total" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path, headers: FRAME
    assert_response :success
    assert_match "~$4.50", response.body          # per-item estimate
    assert_match "Estimated total", response.body
    assert_match "$4.50", response.body           # total (single item)
  end

  test "scales by stations: 12 booked => 6 stations" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path, headers: FRAME
    assert_equal 6, @captured.first[:stations]
  end

  test "a 2-person-per-ticket override doubles the headcount, so stations double" do
    url = add_class("Pasta Night", "groc-pasta", 1, booked: 12) # 12 tickets, neutral name
    get nyk_grocery_path, headers: FRAME
    assert_equal 6, @captured.first[:stations] # 12 people => 6 stations by default

    patch nyk_grocery_portion_path, params: { url: url, people_per_ticket: 2 }
    get nyk_grocery_path, headers: FRAME
    assert_equal 12, @captured.first[:stations] # 12 tickets × 2 = 24 people => 12 stations

    # Clearing falls back to auto-detect (here, no signal, so default 1).
    patch nyk_grocery_portion_path, params: { url: url, people_per_ticket: "" }
    get nyk_grocery_path, headers: FRAME
    assert_equal 6, @captured.first[:stations]
  end

  test "embeds per-class recipe data and interactive tag chips for the popover" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path, headers: FRAME
    assert_response :success
    assert_match 'data-controller="recipe-popover"', response.body
    assert_match "data-recipe-popover-recipes-value", response.body
    assert_match "Flour", response.body                                  # recipe line in the embedded data
    assert_match 'data-recipe-popover-item-param="Flour"', response.body # item chip carries the row's item
  end

  test "flags in-range classes that have no recipe and excludes them" do
    add_class("Has Recipe", "groc-has", 1, booked: 8)
    add_class("No Recipe", "groc-no", 1, booked: 4, recipe: false)
    get nyk_grocery_path, headers: FRAME
    assert_response :success
    assert_match "No Recipe", response.body
    assert_match "no recipe", response.body
    assert_equal 1, @captured.size # only the class with a recipe goes to the aggregator
  end

  test "empty when no in-range class has a recipe" do
    add_class("Future No Recipe", "groc-fut", 1, booked: 4, recipe: false)
    get nyk_grocery_path, headers: FRAME
    assert_response :success
    assert_match "No classes in this range have a recipe", response.body
  end

  test "includes sold-out classes (the fullest ones to shop for)" do
    url = "https://nykitchen.com/event/groc-soldout/"
    @snap.kitchen_events.create!(name: "Sold Out Dinner", url: url, start_at: 1.day.from_now.change(hour: 18),
                                 availability: "SoldOut", capacity: 20, spots_left: 0)
    h = KitchenHandout.create!(title: "Sold Out Dinner", data: { "recipes" => RECIPE })
    h.attach_to!(url)
    get nyk_grocery_path, headers: FRAME
    assert_response :success
    assert_match "NY Kitchen Grocery List", response.body
    assert_equal 1, @captured.size
    assert_equal 10, @captured.first[:stations] # 20 booked => 10 stations
  end

  test "days param widens the window" do
    add_class("Far Out", "groc-far", 12, booked: 6)
    get nyk_grocery_path, headers: FRAME # default weekend window excludes day +12
    assert_match "No classes in this range have a recipe", response.body
    get nyk_grocery_path(days: 14), headers: FRAME
    assert_match "NY Kitchen Grocery List", response.body
  end

  test "from/to params scope the list to a specific week" do
    add_class("This week", "groc-now", 1, booked: 8)
    add_class("Two weeks out", "groc-far", 13, booked: 6)
    far = 13.days.from_now.to_date
    get nyk_grocery_path(from: far.beginning_of_week.iso8601, to: far.end_of_week.iso8601), headers: FRAME
    assert_response :success
    assert_equal 1, @captured.size
    assert_equal "Two weeks out", @captured.first[:class_name]
  end

  # --- Pull sheet: the same list scoped to a single class -------------------

  test "the pull sheet shell shows the class and hides the day-range pills" do
    url = add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path(event_url: url, name: "Ravioli") # no Turbo-Frame header
    assert_response :success
    assert_match "Pull sheet", response.body
    assert_match "Ravioli", response.body
    assert_match "Building your grocery list", response.body
    assert_no_match "This weekend", response.body, "day-range pills don't apply to one class"
    assert_equal 0, @agg_calls, "shell must not call the aggregator"
  end

  test "the pull sheet frame builds a list for only the selected class" do
    url = add_class("Ravioli", "groc-rav", 1, booked: 12)
    add_class("Other Class", "groc-other", 1, booked: 8) # also has a recipe, same week
    get nyk_grocery_path(event_url: url, name: "Ravioli"), headers: FRAME
    assert_response :success
    assert_match "NY Kitchen Pull Sheet", response.body
    assert_match "Flour", response.body
    assert_equal 1, @captured.size, "only the selected class goes to the aggregator"
    assert_equal "Ravioli", @captured.first[:class_name]
  end

  test "the pull sheet flags a class that has no recipe" do
    url = add_class("No Recipe", "groc-no", 1, booked: 4, recipe: false)
    get nyk_grocery_path(event_url: url, name: "No Recipe"), headers: FRAME
    assert_response :success
    assert_match "no recipe attached yet", response.body
    assert_equal 0, @agg_calls
  end

  test "the pull sheet hides per-item prices and the estimated total" do
    url = add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path(event_url: url, name: "Ravioli"), headers: FRAME
    assert_response :success
    assert_match "Flour", response.body                 # items still show
    assert_no_match(/~\$4\.50/, response.body)          # no per-item price
    assert_no_match(/Estimated total/, response.body)   # no total
  end

  test "the week grocery list still shows prices (pricing only hidden on the pull sheet)" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path(from: Date.current.iso8601, to: (Date.current + 7).iso8601), headers: FRAME
    assert_response :success
    assert_match "~$4.50", response.body
    assert_match "Estimated total", response.body
  end

  # --- Week card estimated total (read from cache, never re-bills) -----------

  test "the week grocery card shows the estimated total once the list is built" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    # Warm the cache. The key is the recipe set (not the date range), so any
    # range covering the class produces the same key the list card reads.
    get nyk_grocery_path(from: Date.current.iso8601, to: (Date.current + 7).iso8601), headers: FRAME
    assert_equal 1, @agg_calls

    get nyk_list_path
    assert_response :success
    assert_match "est. total", response.body
    assert_equal 1, @agg_calls, "the list render must not re-bill the aggregator"
  ensure
    Rails.cache = original
  end

  test "the week grocery card omits the total when no list is cached yet" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_list_path
    assert_response :success
    assert_no_match "est. total", response.body
    assert_equal 0, @agg_calls, "a cold list render never calls the aggregator"
  end

  # --- Background warm job: populates the card total without a manual visit ---

  test "a cold list render enqueues a background warm for the week" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    assert_enqueued_with(job: GroceryListWarmJob) { get nyk_list_path }
    assert_equal 0, @agg_calls, "enqueue only; the job runs later"
  end

  test "a week with no recipe does not enqueue a warm job" do
    add_class("No Recipe", "groc-no", 1, booked: 4, recipe: false)
    assert_no_enqueued_jobs(only: GroceryListWarmJob) { get nyk_list_path }
  end

  test "a cached week does not enqueue another warm job" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path(from: Date.current.iso8601, to: (Date.current + 7).iso8601), headers: FRAME # warm
    assert_no_enqueued_jobs(only: GroceryListWarmJob) { get nyk_list_path }
  ensure
    Rails.cache = original
  end

  test "the warm job builds and caches the week's list" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    add_class("Ravioli", "groc-rav", 1, booked: 12)

    GroceryListWarmJob.perform_now(Date.current.iso8601, (Date.current + 7).iso8601)
    assert_equal 1, @agg_calls, "the job builds the list once"

    # The list card now reads the warmed total without re-billing.
    get nyk_list_path
    assert_response :success
    assert_match "est. total", response.body
    assert_equal 1, @agg_calls, "the list render reuses the warmed cache"
  ensure
    Rails.cache = original
  end

  test "caches the aggregation: same recipe set does not re-bill Claude" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    add_class("Ravioli", "groc-rav", 1, booked: 12)

    get nyk_grocery_path, headers: FRAME
    get nyk_grocery_path, headers: FRAME # same inputs -> served from cache
    assert_equal 1, @agg_calls, "aggregator should run once, then hit cache"
    assert_match "Saved list (no new AI cost)", response.body
  ensure
    Rails.cache = original
  end
end
