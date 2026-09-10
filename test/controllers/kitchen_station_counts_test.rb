require "test_helper"
require "ostruct"

# Double and single station counts per class (Lora and Caitlin, 2026-09-10).
# Doubles cook the full "Double" amounts, singles the half "Single" amounts.
# The grocery math buys doubles x Double + singles x Single, the pull sheet
# shows and edits the counts, and the packet prints them above each recipe.
class KitchenStationCountsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  FRAME = { "Turbo-Frame" => "grocery_list" }.freeze
  RECIPE = [ { "title" => "Ravioli",
               "ingredients" => [ { "qty" => "2 c", "station_qty" => "1 c", "item" => "Flour", "section" => nil } ],
               "directions" => [ { "section" => nil, "steps" => [ "Mix." ] } ] } ].freeze
  AGG = { "categories" => [ { "name" => "Pantry", "items" => [ { "quantity" => "4 c", "item" => "Flour", "price" => 1.2, "classes" => [ "Ravioli" ] } ] } ],
          "to_taste" => [ "salt" ] }.freeze

  setup do
    travel_to Time.zone.local(2026, 6, 17, 12, 0)
    @user = User.create!(email_address: "st-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(@user)
    @nyk = nyk_workspace!(owner: @user)
    @snap = KitchenSnapshot.create!(taken_on: Date.current)
    @url = "https://nykitchen.com/event/st-ravioli/"
    @event = @snap.kitchen_events.create!(name: "Ravioli", url: @url, start_at: 2.days.from_now.change(hour: 18),
                                          availability: "InStock", capacity: 24, spots_left: 17) # 7 booked
    @packet = KitchenPacket.create!(title: "Ravioli", data: { "recipes" => RECIPE })
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
    get nyk_grocery_path(event_url: @url, name: "Ravioli"), headers: FRAME
    perform_enqueued_jobs
    get nyk_grocery_path(event_url: @url, name: "Ravioli"), headers: FRAME
    response.body
  end

  def weekly
    get nyk_grocery_path(generate: 1), headers: FRAME
    perform_enqueued_jobs
    get nyk_grocery_path, headers: FRAME
    response.body
  end

  # ---- model ----

  test "default counts reproduce the old math: every booked pair is one single station, no doubles" do
    sc = @event.station_counts
    assert_equal 0, sc.doubles
    assert_equal 4, sc.singles # 7 people => ceil(3.5)
    refute sc.overridden?
    assert_equal "4 single stations", sc.label

    empty = @snap.kitchen_events.create!(name: "Nobody", url: "https://nykitchen.com/event/nobody/", start_at: 3.days.from_now,
                                         availability: "InStock", capacity: 10, spots_left: 10)
    assert_equal 1, empty.station_counts.singles # at least one station so the class still contributes
  end

  test "by-hand counts are stored per url, clamped, and cleared when both are zero" do
    KitchenEvent.set_station_counts(@url, doubles: "3", singles: "1")
    sc = @event.station_counts
    assert_equal [ 3, 1, true ], [ sc.doubles, sc.singles, sc.overridden? ]
    assert_equal 4, sc.total
    assert_equal "3 double stations, 1 single station", sc.label

    KitchenEvent.set_station_counts(@url, doubles: 500, singles: -2)
    assert_equal [ KitchenEvent::MAX_STATIONS, 0 ], @event.station_counts.to_a.first(2)
    assert_equal "99 double stations", @event.station_counts.label

    KitchenEvent.set_station_counts(@url, doubles: "", singles: 0)
    refute @event.station_counts.overridden?
    assert_nil Setting.get("#{KitchenEvent::STATIONS_OVERRIDE_PREFIX}#{@url}")

    # Junk in the setting falls back to the default instead of raising.
    Setting.set("#{KitchenEvent::STATIONS_OVERRIDE_PREFIX}#{@url}", "not json")
    assert_equal 4, @event.station_counts.singles
  end

  # ---- grocery math ----

  test "the aggregator gets both counts and both amounts, and the prompt spells out the math" do
    KitchenEvent.set_station_counts(@url, doubles: 3, singles: 1)
    sheet
    it = @captured.first
    assert_equal [ 3, 1, 4 ], [ it[:doubles], it[:singles], it[:stations] ]

    prompt = KitchenAi::GroceryAggregator.new.send(:build_prompt, @captured)
    assert_match "3 double stations, 1 single stations", prompt
    assert_match "Flour: DOUBLE 2 c | SINGLE 1 c", prompt
    assert_match "double stations x DOUBLE amount", KitchenAi::GroceryAggregator::SYSTEM_PROMPT
  end

  test "a legacy stations-only item is treated as all singles" do
    prompt = KitchenAi::GroceryAggregator.new.send(:build_prompt, [ { class_name: "Old", stations: 5, recipes: RECIPE } ])
    assert_match "0 double stations, 5 single stations", prompt
  end

  test "changing the counts rebuilds the list and flags a hand-edited sheet as stale" do
    sheet
    assert_equal [ 0, 4 ], [ @captured.first[:doubles], @captured.first[:singles] ]
    assert_match "4 single stations", response.body
    assert_match "auto from bookings", response.body

    key = KitchenAi::GroceryList.cache_key(KitchenAi::GroceryList.new.with_recipe([ @event ]))
    @nyk.pull_sheet_edits.create!(event_url: @url, base_key: key, categories: [ { "name" => "Pantry", "items" => [ { "quantity" => "9 c", "item" => "Flour" } ] } ])

    patch nyk_grocery_stations_path, params: { url: @url, doubles: 2, singles: 3 }
    assert_response :redirect

    body = sheet
    assert_match "2 double stations, 3 single stations", body
    assert_match "set by hand", body
    assert_match "The recipes or station counts changed since", body

    # Reset the edit: the regenerated list is built with the new counts.
    delete nyk_pull_sheet_path, params: { event_url: @url, name: "Ravioli" }
    sheet
    assert_equal [ 2, 3 ], [ @captured.first[:doubles], @captured.first[:singles] ]
  end

  test "the counts flow into the PDF and the spreadsheet headers" do
    KitchenEvent.set_station_counts(@url, doubles: 2, singles: 1)
    sheet
    get nyk_grocery_path(event_url: @url, name: "Ravioli", download: 1)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    pdf = KitchenGroceryPdf.new(result: KitchenAi::GroceryAggregator::Result.new(ok?: true, categories: [], to_taste: []),
                                with_recipe: KitchenAi::GroceryList.new.with_recipe([ @event ]), range: Date.current..Date.current,
                                total_headcount: 7, single: true, single_event: @event)
    assert_equal "2 double stations, 1 single station", pdf.send(:stations_label, pdf.instance_variable_get(:@with_recipe).first)

    get nyk_grocery_path(event_url: @url, name: "Ravioli", download: 1, xlsx: 1)
    require "zip"
    xml = nil
    Zip::File.open_buffer(response.body.b) { |z| xml = z.get_input_stream("xl/worksheets/sheet1.xml").read }
    assert_match "2 double stations, 1 single station", xml
  end

  test "the weekly list has a stations form per class" do
    body = weekly
    assert_match "Stations per class", body
    assert_select "form[action=?]", nyk_grocery_stations_path
    assert_select "input[name=doubles][value='0']"
    assert_select "input[name=singles][value='4']"
  end

  test "blank url is rejected and a non-member cannot set counts" do
    patch nyk_grocery_stations_path, params: { doubles: 1, singles: 1 }
    assert_response :bad_request

    stranger = User.create!(email_address: "str-#{SecureRandom.hex(3)}@example.com")
    sign_in_as(stranger)
    patch nyk_grocery_stations_path, params: { url: @url, doubles: 9, singles: 9 }
    assert_response :not_found
    refute @event.station_counts.overridden?
  end

  # ---- packet ----

  test "the packet prints the class's station counts above each recipe, and the print page carries the run" do
    KitchenEvent.set_station_counts(@url, doubles: 3, singles: 1)
    get print_nyk_packet_path(@packet, format: :pdf)
    assert_response :success
    assert_equal "application/pdf", response.media_type

    # Embedded-font text is glyph-encoded in the PDF bytes, so capture the
    # strings a recipe page draws instead (same trick as kitchen_packet_pdf_test).
    texts = page_texts(KitchenPacketPdf.new(@packet, event: @event))
    assert_includes texts, "3 double stations, 1 single station"
    assert_equal texts.index("Ravioli") + 1, texts.index("3 double stations, 1 single station"), "counts sit right under the title"

    get print_nyk_packet_path(@packet)
    assert_response :success
    assert_match "event_url=#{CGI.escape(@url)}", response.body
    assert_match "v=#{@packet.updated_at.to_i}-3-1", response.body

    # A packet with no class run prints no station line.
    loose = KitchenPacket.create!(title: "Loose", data: { "recipes" => RECIPE })
    get print_nyk_packet_path(loose, format: :pdf)
    assert_nil KitchenPacketPdf.new(loose).stations_line
    assert_no_match(/station/, page_texts(KitchenPacketPdf.new(loose)).join("\n"))
  end

  def page_texts(pdf)
    doc = Prawn::Document.new
    texts = []
    doc.define_singleton_method(:text) { |str, *_| texts << str }
    doc.define_singleton_method(:table) { |*_| nil }
    doc.define_singleton_method(:make_table) { |*_| Struct.new(:height).new(10) }
    pdf.send(:recipe_page, doc, RECIPE.first, "Double", false)
    texts
  end
end
