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

  test "prints the full upcoming list, not just the TV slide_count" do
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

  test "sold-out classes are excluded from the handout" do
    add_event("Open Class", 24)
    add_event("Gone Class", 48, availability: "SoldOut")
    get nyk_display_print_path
    assert_match    "Open Class", response.body
    assert_no_match(/Gone Class/, response.body)
  end
end
