require "test_helper"
require "ostruct"

# BuildGroceryListJob aggregates + caches the grocery list off the web request,
# so the grocery frame just polls the cache. The aggregator is stubbed (never
# hits the API). We assert it reconstructs the scoped event set, caches under the
# key the page reads, and no-ops when nothing in range has a recipe.
class BuildGroceryListJobTest < ActiveJob::TestCase
  RECIPE = [ { "title" => "Pasta",
               "ingredients" => [ { "qty" => "2 c", "station_qty" => "1 c", "item" => "Flour", "section" => nil } ],
               "directions" => [] } ].freeze
  AGG = { "categories" => [ { "name" => "Pantry and dry goods",
                              "items" => [ { "item" => "Flour", "quantity" => "7 1/2 c", "price" => 4.5, "classes" => [ "Pasta" ] } ] } ],
          "to_taste" => [] }.freeze

  setup do
    # Mid-week so a "+1 day" class lands inside the current Mon-Sun week.
    travel_to Time.zone.local(2026, 6, 17, 12, 0)
    # The job writes to the cache; the test default is :null_store (never keeps
    # anything), so swap in a real store to observe the cached list.
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @snap = KitchenSnapshot.create!(taken_on: Date.current)
    @agg_calls = 0
    @captured = nil
    KitchenAi::GroceryAggregator.stub = lambda do |items:|
      @agg_calls += 1
      @captured = items
      OpenStruct.new(content: [ OpenStruct.new(text: AGG.to_json) ],
                     usage: OpenStruct.new(input_tokens: 10, output_tokens: 10))
    end
  end

  teardown do
    KitchenAi::GroceryAggregator.stub = nil
    Rails.cache = @original_cache
  end

  def add_class(name, slug, days_out, booked:, recipe: true)
    url = "https://nykitchen.com/event/#{slug}/"
    @snap.kitchen_events.create!(name: name, url: url, start_at: days_out.days.from_now.change(hour: 18),
                                 availability: "InStock", capacity: 24, spots_left: 24 - booked)
    KitchenPacket.create!(title: name, data: { "recipes" => RECIPE }).attach_to!(url) if recipe
    url
  end

  def week_scope
    { "from" => Date.current.beginning_of_week(:monday).to_s,
      "to"   => Date.current.end_of_week(:monday).to_s }
  end

  test "a date-window scope aggregates the in-range classes and caches the list" do
    add_class("Pasta", "bg-pasta", 1, booked: 12)
    BuildGroceryListJob.perform_now(week_scope)
    assert_equal 1, @agg_calls

    # The list is now cached under the exact key the grocery frame reads.
    svc = KitchenAi::GroceryList.new(user: nil)
    wr  = svc.with_recipe(@snap.kitchen_events.upcoming.to_a)
    result, from_cache = svc.fetch(wr, write: false)
    assert from_cache, "the job should have cached the list for the frame to read"
    assert result.ok?
  end

  test "a single-class scope aggregates only that class" do
    url = add_class("Pasta", "bg-pasta", 1, booked: 12)
    add_class("Other", "bg-other", 1, booked: 8) # same week, also has a recipe
    BuildGroceryListJob.perform_now({ "event_url" => url })
    assert_equal 1, @agg_calls
    assert_equal 1, @captured.size, "only the scoped class goes to the aggregator"
    assert_equal "Pasta", @captured.first[:class_name]
  end

  test "no class in range has a recipe -> no aggregation, no cost" do
    add_class("No Recipe", "bg-no", 1, booked: 4, recipe: false)
    BuildGroceryListJob.perform_now(week_scope)
    assert_equal 0, @agg_calls
  end

  test "a scope that matches no events is a safe no-op" do
    add_class("Pasta", "bg-pasta", 1, booked: 12)
    assert_nothing_raised { BuildGroceryListJob.perform_now({ "event_url" => "https://nykitchen.com/event/nope/" }) }
    assert_equal 0, @agg_calls
  end

  test "a malformed date scope is a safe no-op" do
    add_class("Pasta", "bg-pasta", 1, booked: 12)
    assert_nothing_raised { BuildGroceryListJob.perform_now({ "from" => "not-a-date", "to" => "nope" }) }
    assert_equal 0, @agg_calls
  end

  test "flips the navbar build status to ready when it finishes" do
    add_class("Pasta", "bg-pasta", 1, booked: 12)
    svc = KitchenAi::GroceryList.new(user: nil)
    key = KitchenAi::GroceryList.cache_key(svc.with_recipe(@snap.kitchen_events.upcoming.to_a), svc.observed_prices)
    GroceryBuildStatus.start(user_id: 7, token: key, title: "Grocery list", url: "/nykitchen/grocery")
    BuildGroceryListJob.perform_now(week_scope, 7)
    assert_equal "ready", GroceryBuildStatus.current(7)[:status]
  end

  test "runs on the low-concurrency extraction queue" do
    assert_equal "extraction", BuildGroceryListJob.new.queue_name
  end
end
