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

  test "third line shows the class blurb, with the scraped title/date header stripped" do
    add_event("Italian Classics Cooking Class", 24,
      description: "<p>Italian Cla ic  Cooking Cla  5/31/26</p>" \
                   "<p>Sunday May 31 @ 5:00 pm - 7:00 pm</p>" \
                   "<p>Join the New York Kitchen Culinary Team for a hands-on tour of regional Italian cooking.</p>")
    get nyk_display_print_path
    assert_response :success
    assert_select ".desc", /Join the New York Kitchen Culinary Team/
    assert_no_match(/Cla ic  Cooking/, response.body) # mangled title header dropped
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

  test "menu replaces the description blurb when present" do
    add_event("Strawberries Class", 24,
      menu: "Strawberry Crostini / Strawberry Basil Chicken",
      description: "A lovely class about strawberries and friendship.")
    get nyk_display_print_path
    assert_response :success
    assert_match "Menu:", response.body
    assert_match "Strawberry Crostini / Strawberry Basil Chicken", response.body
    assert_no_match "lovely class about strawberries", response.body
  end

  test "blurb fallback strips bolded booking disclosures" do
    add_event("Chefs Table", 24,
      description: "**PLEASE NOTE THAT 1 TICKET IS FOR 2 PEOPLE.** Everyone wants a seat at the Chefs Table!")
    get nyk_display_print_path
    assert_response :success
    assert_match "Everyone wants a seat", response.body
    assert_no_match "PLEASE NOTE THAT 1 TICKET", response.body
  end

  test "photos render at 16:9, not square" do
    add_event("Wide Photo Class", 24, image_url: "https://img.test/a.jpg")
    get nyk_display_print_path
    assert_match(/\.thumb \{\s*width: 1\.46in; height: 0\.82in/, response.body)
    get nyk_display_print_path(variant: "stall")
    assert_match(/\.thumb \{\s*width: 1\.87in; height: 1\.05in/, response.body)
  end
end
