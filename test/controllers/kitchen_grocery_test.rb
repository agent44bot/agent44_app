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
    # Freeze to a mid-week day so "+1 day" classes always fall inside the
    # current Mon-Sun week, regardless of which weekday the suite runs on.
    travel_to Time.zone.local(2026, 6, 17, 12, 0)
    @user = User.create!(email_address: "groc-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(@user)
    # Grocery price estimates are hidden by default until real prices are
    # uploaded; flip the workspace toggle on so the existing price-display
    # assertions below exercise the visible path. A dedicated test covers off.
    @nyk = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @user }
    @nyk.update!(show_grocery_prices: true)
    @snap = KitchenSnapshot.create!(taken_on: Date.current)
    # The list builds in the background now and the frame reads it from the cache
    # on the next poll, so the tests need a cache that actually persists between
    # requests (the test default is :null_store, which never keeps anything).
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @agg_calls = 0
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

  def add_class(name, slug, days_out, booked:, cap: 24, recipe: true)
    url = "https://nykitchen.com/event/#{slug}/"
    @snap.kitchen_events.create!(name: name, url: url, start_at: days_out.days.from_now.change(hour: 18),
                                 availability: "InStock", capacity: cap, spots_left: cap - booked)
    if recipe
      h = KitchenPacket.create!(title: name, data: { "recipes" => RECIPE })
      h.attach_to!(url)
    end
    url
  end

  # The list now builds in the background: the first frame request kicks off
  # BuildGroceryListJob and returns "building"; the job aggregates + caches; the
  # next frame request renders the finished list. This helper runs that whole
  # cycle and leaves `response` on the final, built list.
  def frame_grocery(**params)
    # The main list waits for a Generate click before billing, so trigger the
    # build explicitly (generate: 1). Pull sheets (event_url) build on their own.
    get nyk_grocery_path(**params.merge(generate: 1)), headers: FRAME
    perform_enqueued_jobs
    get nyk_grocery_path(**params), headers: FRAME
  end

  test "the page shell loads fast with a spinner and does not build the list" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path # no Turbo-Frame header
    assert_response :success
    assert_match "Building your grocery list", response.body
    assert_no_match "NY Kitchen Grocery List", response.body
    assert_equal 0, @agg_calls, "shell must not call the aggregator"
  end

  test "the grocery shell offers a custom From/To date range picker" do
    get nyk_grocery_path
    assert_response :success
    assert_select "input[type=date][name=from]"
    assert_select "input[type=date][name=to]"
    assert_select "form[method=get] button[type=submit]", text: /Generate/
  end

  test "the picker defaults From to today, not the past Monday of the week" do
    get nyk_grocery_path # default current-week view (range starts Monday)
    assert_response :success
    assert_select "input[name=from][value=?]", Date.current.iso8601
  end

  test "a custom from/to range fills the picker with those dates" do
    from = Date.current.iso8601
    to   = (Date.current + 10).iso8601
    get nyk_grocery_path(from: from, to: to)
    assert_response :success
    assert_select "input[name=from][value=?]", from
    assert_select "input[name=to][value=?]", to
  end

  # --- Background build: the frame never blocks on the slow Claude call --------

  test "a cold frame waits for Generate and never bills on a plain visit" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    assert_no_enqueued_jobs do
      get nyk_grocery_path, headers: FRAME
    end
    assert_response :success
    assert_match "Generate grocery list", response.body
    assert_no_match "Building your grocery list", response.body
    assert_no_match "NY Kitchen Grocery List", response.body
    assert_equal 0, @agg_calls, "a plain visit never calls the aggregator"
  end

  test "hitting Generate kicks off one background build and shows the building state" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    assert_enqueued_with(job: BuildGroceryListJob) do
      get nyk_grocery_path(generate: 1), headers: FRAME
    end
    assert_response :success
    assert_match "Building your grocery list", response.body
    assert_match 'data-controller="grocery-poll"', response.body
    assert_no_match "NY Kitchen Grocery List", response.body
    assert_equal 0, @agg_calls, "the request itself never calls the aggregator"
  end

  test "polling the frame before the build finishes enqueues only one job" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    assert_enqueued_jobs 1, only: BuildGroceryListJob do
      get nyk_grocery_path(generate: 1), headers: FRAME
      get nyk_grocery_path(generate: 1), headers: FRAME # a poll before the job runs
    end
  end

  test "the background build caches the list the next poll renders" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path(generate: 1), headers: FRAME  # building; enqueues the job
    assert_match "Building your grocery list", response.body
    perform_enqueued_jobs                  # the job aggregates + caches
    assert_equal 1, @agg_calls
    get nyk_grocery_path, headers: FRAME  # cache hit -> the finished list
    assert_match "NY Kitchen Grocery List", response.body
    assert_match "Flour", response.body
  end

  test "a cold frame registers the build so the navbar bar can track it" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path(generate: 1), headers: FRAME
    g = GroceryBuildStatus.current(@user.id)
    assert g, "the build should be registered for the app-wide navbar bar"
    assert_equal "building", g[:status]

    # The same active_builds feed the recipe bar polls now surfaces it.
    get nyk_active_builds_path, headers: { "Accept" => "application/json" }
    assert_response :success
    groc = JSON.parse(response.body)["builds"].find { |b| b["id"].to_s.start_with?("grocery-") }
    assert groc, "active_builds should surface the in-flight grocery build"
    assert_equal "building", groc["status"]
    assert_equal "grocery", groc["stage"]
    assert_match(/grocery list/i, groc["done_label"])

    # When the build finishes, the bar entry flips to "ready".
    perform_enqueued_jobs
    get nyk_active_builds_path, headers: { "Accept" => "application/json" }
    groc = JSON.parse(response.body)["builds"].find { |b| b["id"].to_s.start_with?("grocery-") }
    assert_equal "ready", groc["status"]
  end

  test "grocery list honors the per-feature model override" do
    AiModelChoice.set("nyk_grocery_list", "haiku") # default is Opus
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    frame_grocery
    assert_response :success
    log = AiCallLog.where(source: "nyk_grocery_list").last
    assert_equal "claude-haiku-4-5-20251001", log.model
  end

  test "the grocery shell shows week-aligned date pills" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    get nyk_grocery_path # shell, no Turbo-Frame header
    assert_response :success
    mon = Date.current.beginning_of_week(:monday)
    sun = Date.current.end_of_week(:monday)

    assert_no_match(/This weekend/, response.body)
    assert_match "Current week", response.body
    assert_match "Next week", response.body
    assert_match "Next 2 weeks", response.body
    assert_no_match(/Next 7 days/, response.body)
    assert_no_match(/Next 14 days/, response.body)

    # Week pills link to Mon-Sun ranges; "Next 2 weeks" = this week + next.
    assert_match ERB::Util.html_escape(nyk_grocery_path(from: mon.iso8601, to: sun.iso8601)), response.body
    assert_match ERB::Util.html_escape(nyk_grocery_path(from: (mon + 7).iso8601, to: (sun + 7).iso8601)), response.body
    assert_match ERB::Util.html_escape(nyk_grocery_path(from: mon.iso8601, to: (sun + 7).iso8601)), response.body
  end

  test "the frame renders the aggregated list with item class tags" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    frame_grocery
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
    frame_grocery
    assert_response :success
    assert_match "2 T", response.body
    assert_match "1/2 c", response.body
    assert_no_match(/2 Tablespoons/, response.body)
    assert_no_match(%r{1/2 cup}, response.body)
  end

  test "shows per-item price and an estimated total" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    frame_grocery
    assert_response :success
    assert_match "~$4.50", response.body          # per-item estimate
    assert_match "Estimated total", response.body
    assert_match "$4.50", response.body           # total (single item)
  end

  test "scales by stations: 12 booked => 6 stations" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    frame_grocery
    assert_equal 6, @captured.first[:stations]
  end

  test "a 2-person-per-ticket override doubles the headcount, so stations double" do
    url = add_class("Pasta Night", "groc-pasta", 1, booked: 12) # 12 tickets, neutral name
    frame_grocery
    assert_equal 6, @captured.first[:stations] # 12 people => 6 stations by default

    patch nyk_grocery_portion_path, params: { url: url, people_per_ticket: 2 }
    frame_grocery
    assert_equal 12, @captured.first[:stations] # 12 tickets × 2 = 24 people => 12 stations

    # Clearing falls back to auto-detect (here, no signal, so default 1). The
    # 1-person list has the same cache key as the first build, so drop the cache
    # to force a fresh aggregation and re-inspect the captured stations.
    Rails.cache.clear
    patch nyk_grocery_portion_path, params: { url: url, people_per_ticket: "" }
    frame_grocery
    assert_equal 6, @captured.first[:stations]
  end

  test "embeds per-class recipe data and interactive tag chips for the popover" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    frame_grocery
    assert_response :success
    assert_match 'data-controller="recipe-popover"', response.body
    assert_match "data-recipe-popover-recipes-value", response.body
    assert_match "Flour", response.body                                  # recipe line in the embedded data
    assert_match 'data-recipe-popover-item-param="Flour"', response.body # item chip carries the row's item
  end

  test "flags in-range classes that have no recipe and excludes them" do
    add_class("Has Recipe", "groc-has", 1, booked: 8)
    add_class("No Recipe", "groc-no", 1, booked: 4, recipe: false)
    frame_grocery
    assert_response :success
    assert_match "No Recipe", response.body
    assert_match "no recipe", response.body
    assert_equal 1, @captured.size # only the class with a recipe goes to the aggregator
  end

  test "empty when no in-range class has a recipe" do
    add_class("Future No Recipe", "groc-fut", 1, booked: 4, recipe: false)
    frame_grocery
    assert_response :success
    assert_match "No classes in this range have a recipe", response.body
  end

  test "includes sold-out classes (the fullest ones to shop for)" do
    url = "https://nykitchen.com/event/groc-soldout/"
    @snap.kitchen_events.create!(name: "Sold Out Dinner", url: url, start_at: 1.day.from_now.change(hour: 18),
                                 availability: "SoldOut", capacity: 20, spots_left: 0)
    h = KitchenPacket.create!(title: "Sold Out Dinner", data: { "recipes" => RECIPE })
    h.attach_to!(url)
    frame_grocery
    assert_response :success
    assert_match "NY Kitchen Grocery List", response.body
    assert_equal 1, @captured.size
    assert_equal 10, @captured.first[:stations] # 20 booked => 10 stations
  end

  test "days param widens the window" do
    add_class("Far Out", "groc-far", 12, booked: 6)
    frame_grocery # default weekend window excludes day +12
    assert_match "No classes in this range have a recipe", response.body
    frame_grocery(days: 14)
    assert_match "NY Kitchen Grocery List", response.body
  end

  test "from/to params scope the list to a specific week" do
    add_class("This week", "groc-now", 1, booked: 8)
    add_class("Two weeks out", "groc-far", 13, booked: 6)
    far = 13.days.from_now.to_date
    frame_grocery(from: far.beginning_of_week.iso8601, to: far.end_of_week.iso8601)
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
    frame_grocery(event_url: url, name: "Ravioli")
    assert_response :success
    assert_match "NY Kitchen Pull Sheet", response.body
    assert_match "Flour", response.body
    assert_equal 1, @captured.size, "only the selected class goes to the aggregator"
    assert_equal "Ravioli", @captured.first[:class_name]
  end

  test "the pull sheet flags a class that has no recipe" do
    url = add_class("No Recipe", "groc-no", 1, booked: 4, recipe: false)
    frame_grocery(event_url: url, name: "No Recipe")
    assert_response :success
    assert_match "no recipe attached yet", response.body
    assert_equal 0, @agg_calls
  end

  test "the pull sheet lists per-station AND to-purchase equipment" do
    url = add_class("Ravioli", "groc-rav", 1, booked: 12)
    h = KitchenPacket.for_event_url(url)
    h.equipment = [ "Large stockpot", "Wooden spoon" ]
    h.purchase_equipment = [ "Pasta machine" ]
    h.save!
    frame_grocery(event_url: url, name: "Ravioli")
    assert_response :success
    assert_match "Equipment per station", response.body
    assert_match "Large stockpot", response.body
    assert_match "Equipment to purchase", response.body
    assert_match "Pasta machine", response.body
  end

  test "the week grocery list shows equipment to purchase, not per-station gear" do
    url = add_class("Ravioli", "groc-rav", 1, booked: 12)
    h = KitchenPacket.for_event_url(url)
    h.equipment = [ "Large stockpot" ]        # per-station: pull sheet only
    h.purchase_equipment = [ "Pasta machine" ] # to buy: also the grocery list
    h.save!
    frame_grocery(from: Date.current.iso8601, to: (Date.current + 7).iso8601)
    assert_response :success
    assert_match "Equipment to purchase", response.body
    assert_match "Pasta machine", response.body
    refute_match "Equipment per station", response.body
    refute_match "Large stockpot", response.body
  end

  test "the pull sheet hides per-item prices and the estimated total" do
    url = add_class("Ravioli", "groc-rav", 1, booked: 12)
    frame_grocery(event_url: url, name: "Ravioli")
    assert_response :success
    assert_match "Flour", response.body                 # items still show
    assert_no_match(/~\$4\.50/, response.body)          # no per-item price
    assert_no_match(/Estimated total/, response.body)   # no total
  end

  test "the week grocery list still shows prices (pricing only hidden on the pull sheet)" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    frame_grocery(from: Date.current.iso8601, to: (Date.current + 7).iso8601)
    assert_response :success
    assert_match "~$4.50", response.body
    assert_match "Estimated total", response.body
  end

  test "hides per-item prices and the estimated total when the toggle is off" do
    @nyk.update!(show_grocery_prices: false)
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    frame_grocery(from: Date.current.iso8601, to: (Date.current + 7).iso8601)
    assert_response :success
    assert_match "Flour", response.body                # items still show
    assert_no_match(/~\$4\.50/, response.body)         # no per-item price
    assert_no_match(/Estimated total/, response.body)  # no total
  end

  # --- Week card estimated total (read from cache, never re-bills) -----------

  test "the week grocery card shows the estimated total once the list is built" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    # Warm the cache. The key is the recipe set (not the date range), so any
    # range covering the class produces the same key the list card reads.
    frame_grocery(from: Date.current.iso8601, to: (Date.current + 7).iso8601)
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

  test "the week grocery card omits the total when the toggle is off, even if cached" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @nyk.update!(show_grocery_prices: false)
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    # Warm the cache so a total exists; the card must still hide it.
    frame_grocery(from: Date.current.iso8601, to: (Date.current + 7).iso8601)
    assert_equal 1, @agg_calls

    get nyk_list_path
    assert_response :success
    assert_no_match "est. total", response.body
  ensure
    Rails.cache = original
  end

  test "grocery + receipt tools sit once at the top, not once per week" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)  # current week
    add_class("Tacos",   "groc-tac", 8, booked: 10)  # next week
    get nyk_list_path
    assert_response :success
    # One grocery entry point and one receipt uploader for the whole page.
    assert_select "a[href=?]", nyk_grocery_path, 1
    assert_select "form[action=?]", nyk_grocery_receipts_path, 1
    assert_match "Combined shopping list, pick any date range", response.body
  end

  # --- Click-only billing: the card total appears only after a grocery visit ---

  test "a cold list render never bills Opus in the background" do
    add_class("Ravioli", "groc-rav", 1, booked: 12)
    assert_no_enqueued_jobs { get nyk_list_path }
    assert_equal 0, @agg_calls, "no background warm; the list render never aggregates"
  end

  test "opening a week's grocery page populates the list-card total" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    add_class("Ravioli", "groc-rav", 1, booked: 12)

    # Cold: no total yet because nobody has opened the grocery page.
    get nyk_list_path
    assert_response :success
    assert_no_match "est. total", response.body
    assert_equal 0, @agg_calls

    # Opening the grocery page builds + caches the list (the one paid call).
    frame_grocery(from: Date.current.iso8601, to: (Date.current + 7).iso8601)
    assert_equal 1, @agg_calls, "the grocery visit builds the list once"

    # The list card now reads the cached total without re-billing.
    get nyk_list_path
    assert_response :success
    assert_match "est. total", response.body
    assert_equal 1, @agg_calls, "the list render reuses the cache"
  ensure
    Rails.cache = original
  end

  test "caches the aggregation: same recipe set does not re-bill Claude" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    add_class("Ravioli", "groc-rav", 1, booked: 12)

    frame_grocery
    frame_grocery # same inputs -> served from cache
    assert_equal 1, @agg_calls, "aggregator should run once, then hit cache"
    assert_match "Saved list (no new AI cost)", response.body
  ensure
    Rails.cache = original
  end
end
