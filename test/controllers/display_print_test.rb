require "test_helper"

class DisplayPrintTest < ActionDispatch::IntegrationTest
  setup do
    @snapshot = KitchenSnapshot.create!(taken_on: Date.current)
  end

  def add_event(name, hours_from_now, **attrs)
    @snapshot.kitchen_events.create!({
      url: "https://nykitchen.com/event/#{name.parameterize}",
      name: name,
      start_at: hours_from_now.hours.from_now,
      availability: "InStock"
    }.merge(attrs))
  end

  test "flyer is branded New York Kitchen with a calendar QR footer" do
    add_event("Pinot Noir Decoded", 24, image_url: "https://img.test/a.jpg", end_at: 26.hours.from_now)
    get nyk_display_print_path
    assert_response :success
    assert_match "New York Kitchen", response.body
    assert_no_match(/\bNY Kitchen\b/, response.body)            # old short brand gone
    assert_match "Check out other New York Kitchen classes", response.body
    assert_match "nykitchen.com/calendar/", response.body
    # Event time ranges read "6:00 PM to 8:00 PM", no en dash.
    assert_no_match(/\d\s–\s\d/, response.body)
  end

  test "flyer shows the workspace logo when one is attached" do
    owner = User.create!(email_address: "ws-owner-#{SecureRandom.hex(4)}@example.com", role: "user")
    ws = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = owner }
    ws.logo.attach(io: StringIO.new("x" * 64), filename: "logo.png", content_type: "image/png")
    add_event("Pinot Noir Decoded", 24)
    get nyk_display_print_path
    assert_response :success
    assert_select "img.brand-logo", { minimum: 1 }, "brand logo image on the flyer"
  end

  test "renders compact rows with a photo and QR per class" do
    add_event("Pinot Noir Decoded", 24, image_url: "https://img.test/a.jpg", price: "57", spots_left: 25)
    add_event("Chardonnay Faces",   48, image_url: "https://img.test/b.jpg", price: "58", spots_left: 9)

    get nyk_display_print_path
    assert_response :success
    assert_match "Pinot Noir Decoded", response.body
    assert_match "Chardonnay Faces",   response.body
    assert_select "img.thumb", 2, "one photo per class"
    assert_select ".qr svg",   2, "one QR code per class"
    assert_match "$57", response.body
    assert_match "25 spots", response.body
  end

  test "is not limited by the TV slide_count" do
    # slide_count (the rotating-screen cap, default 5) must not truncate the
    # printed flyer; 8 < the one-sheet cap, so all 8 show.
    8.times { |i| add_event("Class #{i}", (i + 1) * 24) }
    get nyk_display_print_path
    assert_response :success
    assert_select ".event", 8
  end

  test "photos=0 prints a text-only schedule but keeps the QR codes" do
    add_event("No Photo Run", 24, image_url: "https://img.test/a.jpg")
    get nyk_display_print_path(photos: 0)
    assert_response :success
    assert_select "img.thumb", 0
    assert_select ".qr svg", 1
  end

  test "descriptions never print, even when the event has one" do
    add_event("Italian Classics Cooking Class", 24,
      description: "<p>Join the New York Kitchen Culinary Team for a hands-on tour.</p>")
    get nyk_display_print_path
    assert_response :success
    assert_select ".desc", 0
    assert_no_match(/Join the New York Kitchen Culinary Team/, response.body)
  end

  test "caps to one double-sided sheet (default 18) and footer-summarizes the rest" do
    25.times { |i| add_event("Class #{format('%02d', i)}", (i + 1) * 24) }
    get nyk_display_print_path
    assert_response :success
    assert_select ".event", 18, "default flyer cap (9 front + 9 back)"
    assert_match "+ 7 more classes", response.body
    # The soonest classes are the ones kept; the latest fall off.
    assert_match    "Class 00", response.body
    assert_no_match(/Class 20/, response.body)
  end

  test "flyer lays out nine classes per side" do
    18.times { |i| add_event("Class #{format('%02d', i)}", (i + 1) * 24) }
    get nyk_display_print_path
    assert_response :success
    assert_select ".page", 2, "18 classes => two sides of nine"
    assert_select ".page:first-of-type .event", 9
  end

  test "stall variant shows six large-font classes with a photo and QR each" do
    8.times { |i| add_event("Class #{format('%02d', i)}", (i + 1) * 24, image_url: "https://img.test/#{i}.jpg") }
    get nyk_display_print_path(variant: "stall")
    assert_response :success
    assert_select ".event", 6, "stall poster caps at six"
    assert_select "img.thumb", 6, "one photo per class"
    assert_select ".qr svg", 6, "one QR per class"
    assert_match "+ 2 more classes", response.body
  end

  test "sold-out and closed classes are excluded from the flyer" do
    add_event("Open Class", 24)
    add_event("Gone Class", 48, availability: "SoldOut")
    add_event("Shut Class", 72, availability: "Closed")
    get nyk_display_print_path
    assert_response :success
    assert_select ".event", 1
    assert_match "Open Class", response.body
    assert_no_match(/Gone Class/, response.body)
    assert_no_match(/Shut Class/, response.body)
  end

  test "no footer overflow note when everything fits" do
    3.times { |i| add_event("Class #{i}", (i + 1) * 24) }
    get nyk_display_print_path
    assert_select ".event", 3
    assert_no_match(/more class/, response.body)
  end

  test "the cap is overridable with ?n=" do
    25.times { |i| add_event("Class #{format('%02d', i)}", (i + 1) * 24) }
    get nyk_display_print_path(n: 5)
    assert_select ".event", 5
    assert_match "+ 20 more classes", response.body
  end

  test "sold-out classes are excluded from the handout" do
    add_event("Open Class", 24)
    add_event("Gone Class", 48, availability: "SoldOut")
    get nyk_display_print_path
    assert_match "Open Class", response.body
    assert_no_match(/Gone Class/, response.body)
  end

  test "neither the menu nor the description prints on the flyer" do
    add_event("Strawberries Class", 24,
      menu: "Strawberry Crostini / Strawberry Basil Chicken",
      description: "A lovely class about strawberries and friendship.")
    get nyk_display_print_path
    assert_response :success
    assert_no_match "Menu:", response.body
    assert_no_match "Strawberry Crostini", response.body
    assert_no_match "lovely class about strawberries", response.body
    assert_select ".desc", 0
  end

  test "photos render at 16:9, not square" do
    add_event("Wide Photo Class", 24, image_url: "https://img.test/a.jpg")
    get nyk_display_print_path
    assert_match(/\.thumb \{\s*width: 1\.46in; height: 0\.82in/, response.body)
    get nyk_display_print_path(variant: "stall")
    assert_match(/\.thumb \{\s*width: 1\.87in; height: 1\.05in/, response.body)
  end

  # --- The link must not break (the front desk relies on it). ---
  # These cover the failure and empty paths someone could hit live: no data,
  # no auth, missing fields, and odd ?n= values.

  test "renders 200 even when no snapshot exists yet (scraper never ran)" do
    KitchenSnapshot.delete_all
    get nyk_display_print_path
    assert_response :success
    get nyk_display_print_path(variant: "stall")
    assert_response :success
  end

  test "renders 200 when the snapshot has zero upcoming classes" do
    # snapshot exists (from setup) but is empty
    get nyk_display_print_path
    assert_response :success
    assert_select ".event", 0
    get nyk_display_print_path(variant: "stall")
    assert_response :success
    assert_select ".event", 0
  end

  test "all past or all sold-out classes still render a 200 (empty schedule)" do
    add_event("Yesterday", -24)
    add_event("Sold Out", 24, availability: "SoldOut")
    get nyk_display_print_path
    assert_response :success
    assert_select ".event", 0
  end

  test "is publicly accessible with no signed-in user (front desk is not logged in)" do
    delete session_path # ensure fully signed out
    add_event("Walk-in Class", 24)
    get nyk_display_print_path
    assert_response :success
    assert_match "Walk-in Class", response.body
    get nyk_display_print_path(variant: "stall")
    assert_response :success
  end

  test "renders both variants when a class is missing photo, price, and spots" do
    # A bare event (no image_url, price, spots_left, or menu) must not crash
    # either template.
    add_event("Bare Class", 24)
    get nyk_display_print_path
    assert_response :success
    assert_match "Bare Class", response.body
    get nyk_display_print_path(variant: "stall")
    assert_response :success
    assert_match "Bare Class", response.body
  end

  test "?n= is clamped to a sane range and never errors" do
    5.times { |i| add_event("Class #{i}", (i + 1) * 24) }
    # zero, negative, non-numeric, and absurdly large all stay safe
    [ "0", "-5", "abc", "9999" ].each do |n|
      get nyk_display_print_path(n: n)
      assert_response :success, "n=#{n} should not error"
      count = css_select(".event").size
      assert count.between?(1, 60), "n=#{n} produced #{count} events, out of range"
    end
  end

  test "opening the print page bumps the flyer print counter and last_at" do
    add_event("Counted Class", 24)
    assert_difference -> { Setting.counter("nyk_flyer_prints:total") }, 1 do
      assert_difference -> { Setting.counter("nyk_flyer_prints:flyer") }, 1 do
        get nyk_display_print_path
      end
    end
    assert Setting.time("nyk_flyer_prints:last_at").present?, "last_at drives Carson's no-flyers nudge"

    assert_difference -> { Setting.counter("nyk_flyer_prints:stall") }, 1 do
      get nyk_display_print_path(variant: "stall")
    end
  end
end
