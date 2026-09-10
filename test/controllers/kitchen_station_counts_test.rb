require "test_helper"
require "ostruct"

# Double and single station counts per RECIPE (Lora and Caitlin, 2026-09-10):
# "4 double salmon, 2 single + 2 double chicken, 10 double orzo". Doubles cook
# the full "Double" amounts, singles the half "Single" amounts. The grocery
# math buys doubles x Double + singles x Single per recipe, the pull sheet
# shows the split, and the packet prints it under each recipe title.
class KitchenStationCountsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  FRAME = { "Turbo-Frame" => "grocery_list" }.freeze
  RECIPES = [
    { "title" => "Salmon", "doubles" => 4, "singles" => 0,
      "ingredients" => [ { "qty" => "2 lb", "station_qty" => "1 lb", "item" => "Salmon", "section" => nil } ],
      "directions" => [ { "section" => nil, "steps" => [ "Sear." ] } ] },
    { "title" => "Chicken", "doubles" => 2, "singles" => 2,
      "ingredients" => [ { "qty" => "4", "station_qty" => "2", "item" => "Chicken thighs", "section" => nil } ],
      "directions" => [ { "section" => nil, "steps" => [ "Roast." ] } ] },
    { "title" => "Orzo",
      "ingredients" => [ { "qty" => "2 c", "station_qty" => "1 c", "item" => "Orzo", "section" => nil } ],
      "directions" => [ { "section" => nil, "steps" => [ "Boil." ] } ] }
  ].freeze
  AGG = { "categories" => [ { "name" => "Pantry", "items" => [ { "quantity" => "4 c", "item" => "Orzo", "price" => 1.2, "classes" => [ "Chef's Table" ] } ] } ],
          "to_taste" => [ "salt" ] }.freeze

  setup do
    travel_to Time.zone.local(2026, 6, 17, 12, 0)
    @user = User.create!(email_address: "st-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(@user)
    @nyk = nyk_workspace!(owner: @user)
    @snap = KitchenSnapshot.create!(taken_on: Date.current)
    @url = "https://nykitchen.com/event/st-chefs-table/"
    @event = @snap.kitchen_events.create!(name: "Chef's Table", url: @url, start_at: 2.days.from_now.change(hour: 18),
                                          availability: "InStock", capacity: 24, spots_left: 17) # 7 booked
    @packet = KitchenPacket.create!(title: "Chef's Table", data: { "recipes" => RECIPES })
    @packet.attach_to!(@url)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @captured = nil
    KitchenAi::GroceryAggregator.stub = lambda do |items:|
      @captured = items
      OpenStruct.new(content: [ OpenStruct.new(text: AGG.to_json) ], usage: OpenStruct.new(input_tokens: 10, output_tokens: 10))
    end
  end

  teardown do
    KitchenAi::GroceryAggregator.stub = nil
    Rails.cache = @original_cache
  end

  def sheet
    get nyk_grocery_path(event_url: @url, name: "Chef's Table"), headers: FRAME
    perform_enqueued_jobs
    get nyk_grocery_path(event_url: @url, name: "Chef's Table"), headers: FRAME
    response.body
  end

  # ---- model ----

  test "a recipe without counts falls back to the booking default: every booked pair is one single station" do
    d = @event.default_station_counts
    assert_equal [ 0, 4, false ], [ d.doubles, d.singles, d.set? ] # 7 people => ceil(3.5)
    assert_equal "4 single stations", d.label

    empty = @snap.kitchen_events.create!(name: "Nobody", url: "https://nykitchen.com/event/nobody/", start_at: 3.days.from_now,
                                         availability: "InStock", capacity: 10, spots_left: 10)
    assert_equal 1, empty.default_station_counts.singles # at least one station so the class still contributes

    assert_same d, KitchenPacket.station_counts_for(RECIPES[2], default: d)
    assert_nil KitchenPacket.station_counts_for(RECIPES[2])
  end

  test "recipe counts are read, clamped, and labeled" do
    sc = KitchenPacket.station_counts_for(RECIPES[1])
    assert_equal [ 2, 2, true, 4 ], [ sc.doubles, sc.singles, sc.set?, sc.total ]
    assert_equal "2 double stations, 2 single stations", sc.label
    assert_equal "2 double, 2 single", sc.short
    assert_equal "4 double stations", KitchenPacket.station_counts_for(RECIPES[0]).label
    assert_equal "1 single station", KitchenPacket.station_counts_for({ "doubles" => 0, "singles" => 1 }).label
    assert_equal "0 stations", KitchenPacket.station_counts_for({ "doubles" => -1, "singles" => 0 }).label
    assert_equal KitchenPacket::MAX_STATIONS, KitchenPacket.station_counts_for({ "doubles" => 500 }).doubles
  end

  test "the class summary lists each recipe's split, and the equipment station count is the busiest recipe" do
    assert_equal "Salmon 4 double; Chicken 2 double, 2 single; Orzo 4 single", KitchenAi::GroceryList.stations_summary(@event, @packet)
    assert_equal 4, KitchenAi::GroceryList.stations(@event, @packet)

    one = KitchenPacket.new(title: "One", data: { "recipes" => [ RECIPES[1] ] })
    assert_equal "2 double stations, 2 single stations", KitchenAi::GroceryList.stations_summary(@event, one)
    assert_equal 10, KitchenAi::GroceryList.stations(@event, KitchenPacket.new(title: "Big", data: { "recipes" => [ RECIPES[2].merge("doubles" => 10, "singles" => 0) ] }))
  end

  # ---- grocery math ----

  test "the aggregator gets each recipe's counts and both amounts, and the prompt spells out the math per recipe" do
    sheet
    recipes = @captured.first[:recipes]
    assert_equal [ [ 4, 0 ], [ 2, 2 ], [ 0, 4 ] ], recipes.map { |r| [ r["doubles"], r["singles"] ] }
    assert_equal 4, @captured.first[:stations]

    prompt = KitchenAi::GroceryAggregator.new.send(:build_prompt, @captured)
    assert_match "Recipe: Salmon (4 double stations, 0 single stations)", prompt
    assert_match "Recipe: Chicken (2 double stations, 2 single stations)", prompt
    assert_match "Recipe: Orzo (0 double stations, 4 single stations)", prompt
    assert_match "Chicken thighs: DOUBLE 4 | SINGLE 2", prompt
    assert_match "using ITS OWN recipe's counts", KitchenAi::GroceryAggregator::SYSTEM_PROMPT
  end

  test "a legacy stations-only item is treated as all singles for every recipe" do
    prompt = KitchenAi::GroceryAggregator.new.send(:build_prompt, [ { class_name: "Old", stations: 5, recipes: [ RECIPES[2] ] } ])
    assert_match "Recipe: Orzo (0 double stations, 5 single stations)", prompt
  end

  test "changing a recipe's counts rebuilds the list and flags a hand-edited sheet as stale" do
    sheet
    key = KitchenAi::GroceryList.cache_key(KitchenAi::GroceryList.new.with_recipe([ @event ]))
    @nyk.pull_sheet_edits.create!(event_url: @url, base_key: key, categories: [ { "name" => "Pantry", "items" => [ { "quantity" => "9 c", "item" => "Orzo" } ] } ])

    recipes = @packet.recipes.map(&:dup)
    recipes[2] = recipes[2].merge("doubles" => 10, "singles" => 0)
    @packet.update!(recipes: recipes)

    body = sheet
    assert_match "Orzo 10 double", body
    assert_match "The recipes or station counts changed since", body

    delete nyk_pull_sheet_path, params: { event_url: @url, name: "Chef's Table" }
    sheet
    assert_equal [ 10, 0 ], [ @captured.first[:recipes][2]["doubles"], @captured.first[:recipes][2]["singles"] ]
  end

  test "a booking change rebuilds the list for recipes on the default" do
    sheet
    first = @captured
    @event.update!(spots_left: 4) # 20 booked => 10 single stations for Orzo
    Rails.cache.clear
    sheet
    refute_same first, @captured
    assert_equal [ 0, 10 ], [ @captured.first[:recipes][2]["doubles"], @captured.first[:recipes][2]["singles"] ]
  end

  # ---- pull sheet ----

  test "the pull sheet shows the split per recipe, links to the editor, and carries it into the PDF and spreadsheet" do
    body = sheet
    assert_match "Salmon 4 double; Chicken 2 double, 2 single; Orzo 4 single", body
    assert_match "Set counts per recipe", body
    assert_select "a[href=?]", edit_nyk_packet_path(@packet)
    assert_match "4 single (auto)", body # the recipe on the booking default is flagged

    get nyk_grocery_path(event_url: @url, name: "Chef's Table", download: 1)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    pdf = KitchenGroceryPdf.new(result: KitchenAi::GroceryAggregator::Result.new(ok?: true, categories: [], to_taste: []),
                                with_recipe: KitchenAi::GroceryList.new.with_recipe([ @event ]), range: Date.current..Date.current,
                                total_headcount: 7, single: true, single_event: @event)
    assert_equal "Salmon 4 double; Chicken 2 double, 2 single; Orzo 4 single", pdf.send(:stations_label, pdf.instance_variable_get(:@with_recipe).first)

    get nyk_grocery_path(event_url: @url, name: "Chef's Table", download: 1, xlsx: 1)
    require "zip"
    xml = nil
    Zip::File.open_buffer(response.body.b) { |z| xml = z.get_input_stream("xl/worksheets/sheet1.xml").read }
    assert_match "Salmon 4 double; Chicken 2 double, 2 single; Orzo 4 single", xml
  end

  # ---- packet ----

  test "the packet prints each recipe's counts under its title, and nothing for a recipe with none set" do
    get print_nyk_packet_path(@packet, format: :pdf)
    assert_response :success
    assert_equal "application/pdf", response.media_type

    # Embedded-font text is glyph-encoded in the PDF bytes, so capture the
    # strings a recipe page draws instead (same trick as kitchen_packet_pdf_test).
    texts = page_texts(RECIPES[1])
    assert_equal texts.index("Chicken") + 1, texts.index("2 double stations, 2 single stations"), "counts sit right under the title"
    assert_includes page_texts(RECIPES[0]), "4 double stations"
    assert_no_match(/station/, page_texts(RECIPES[2]).join("\n"))
  end

  def page_texts(recipe)
    doc = Prawn::Document.new
    texts = []
    doc.define_singleton_method(:text) { |str, *_| texts << str }
    doc.define_singleton_method(:table) { |*_| nil }
    doc.define_singleton_method(:make_table) { |*_| Struct.new(:height).new(10) }
    KitchenPacketPdf.new(@packet).send(:recipe_page, doc, recipe, "Double", false)
    texts
  end
end
