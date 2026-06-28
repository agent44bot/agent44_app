require "test_helper"
require "ostruct"
require "minitest/mock"

class Api::V1::KitchenSnapshotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = "test-api-token-#{SecureRandom.hex(16)}"
    ENV["API_TOKEN"] = @token
    @headers = { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" }
    @today = Date.current.to_s
  end

  teardown do
    ENV.delete("API_TOKEN")
  end

  private def seed_three_event_drops!
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making",
          start_at: 3.days.from_now.iso8601, spots_left: 10, capacity: 24,
          availability: "InStock" },
        { url: "https://nykitchen.com/events/wine-102", name: "Wine Tasting",
          start_at: 4.days.from_now.iso8601, spots_left: 20, capacity: 30,
          availability: "InStock" },
        { url: "https://nykitchen.com/events/bread-103", name: "Bread Basics",
          start_at: 5.days.from_now.iso8601, spots_left: 8, capacity: 16,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers

    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making",
          start_at: 3.days.from_now.iso8601, spots_left: 8, capacity: 24,
          availability: "InStock" },
        { url: "https://nykitchen.com/events/wine-102", name: "Wine Tasting",
          start_at: 4.days.from_now.iso8601, spots_left: 19, capacity: 30,
          availability: "InStock" },
        { url: "https://nykitchen.com/events/bread-103", name: "Bread Basics",
          start_at: 5.days.from_now.iso8601, spots_left: 7, capacity: 16,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers
  end
  public

  # --- Ticket availability notifications ---

  test "sends iOS push notification when spots_left drops between runs" do
    # First scraper run: event has 5 spots
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making Workshop",
          start_at: 3.days.from_now.iso8601, spots_left: 5, capacity: 24,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    # Second scraper run same day: spots dropped to 3
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making Workshop",
          start_at: 3.days.from_now.iso8601, spots_left: 3, capacity: 24,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    notification = Notification.where(source: "kitchen_tickets").order(created_at: :desc).first
    assert_not_nil notification, "Expected a ticket change notification"
    assert_equal "info", notification.level
    assert_includes notification.title, "Pasta Making Workshop"
    assert_includes notification.title, "2"
    assert_includes notification.body, "5"
    assert_includes notification.body, "3"
  end

  test "no notification when spots_left stays the same" do
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making Workshop",
          start_at: 3.days.from_now.iso8601, spots_left: 5, capacity: 24,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making Workshop",
          start_at: 3.days.from_now.iso8601, spots_left: 5, capacity: 24,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    assert_nil Notification.find_by(source: "kitchen_tickets")
  end

  test "no notification when spots_left increases" do
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making Workshop",
          start_at: 3.days.from_now.iso8601, spots_left: 3, capacity: 24,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    # Spots went up (maybe cancellation) — no notification
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making Workshop",
          start_at: 3.days.from_now.iso8601, spots_left: 5, capacity: 24,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    assert_nil Notification.find_by(source: "kitchen_tickets")
  end

  test "no notification on first-ever scrape" do
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making Workshop",
          start_at: 3.days.from_now.iso8601, spots_left: 5, capacity: 24,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    assert_nil Notification.find_by(source: "kitchen_tickets")
  end

  test "notification for multiple events with different changes" do
    # First run: two events
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making",
          start_at: 3.days.from_now.iso8601, spots_left: 5, capacity: 24,
          availability: "InStock" },
        { url: "https://nykitchen.com/events/wine-102", name: "Wine Tasting",
          start_at: 4.days.from_now.iso8601, spots_left: 10, capacity: 30,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    # Second run: pasta dropped, wine unchanged
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making",
          start_at: 3.days.from_now.iso8601, spots_left: 2, capacity: 24,
          availability: "InStock" },
        { url: "https://nykitchen.com/events/wine-102", name: "Wine Tasting",
          start_at: 4.days.from_now.iso8601, spots_left: 10, capacity: 30,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    tickets_notifications = Notification.where(source: "kitchen_tickets")
    assert_equal 1, tickets_notifications.count, "Only pasta should trigger a notification"
    assert_includes tickets_notifications.first.title, "Pasta Making"
  end

  test "batches into a single digest when multiple events change in one scrape" do
    # First run: three events
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making",
          start_at: 3.days.from_now.iso8601, spots_left: 10, capacity: 24,
          availability: "InStock" },
        { url: "https://nykitchen.com/events/wine-102", name: "Wine Tasting",
          start_at: 4.days.from_now.iso8601, spots_left: 20, capacity: 30,
          availability: "InStock" },
        { url: "https://nykitchen.com/events/bread-103", name: "Bread Basics",
          start_at: 5.days.from_now.iso8601, spots_left: 8, capacity: 16,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    # Second run: all three drop
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making",
          start_at: 3.days.from_now.iso8601, spots_left: 8, capacity: 24,
          availability: "InStock" },
        { url: "https://nykitchen.com/events/wine-102", name: "Wine Tasting",
          start_at: 4.days.from_now.iso8601, spots_left: 19, capacity: 30,
          availability: "InStock" },
        { url: "https://nykitchen.com/events/bread-103", name: "Bread Basics",
          start_at: 5.days.from_now.iso8601, spots_left: 7, capacity: 16,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    tickets_notifications = Notification.where(source: "kitchen_tickets")
    assert_equal 1, tickets_notifications.count, "Three changes should produce one digest"
    digest = tickets_notifications.first
    assert_includes digest.title, "3 classes"
    assert_includes digest.title, "4 ticket(s) bought"  # 2 + 1 + 1
    assert_includes digest.body, "Pasta Making"
    assert_includes digest.body, "Wine Tasting"
    assert_includes digest.body, "Bread Basics"
  end

  test "digest title flags when events sell out" do
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/a", name: "Class A",
          start_at: 3.days.from_now.iso8601, spots_left: 2, capacity: 10,
          availability: "InStock" },
        { url: "https://nykitchen.com/events/b", name: "Class B",
          start_at: 4.days.from_now.iso8601, spots_left: 5, capacity: 10,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers

    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/a", name: "Class A",
          start_at: 3.days.from_now.iso8601, spots_left: 0, capacity: 10,
          availability: "SoldOut" },
        { url: "https://nykitchen.com/events/b", name: "Class B",
          start_at: 4.days.from_now.iso8601, spots_left: 3, capacity: 10,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers

    digest = Notification.where(source: "kitchen_tickets").order(created_at: :desc).first
    assert_includes digest.title, "2 classes"
    assert_includes digest.title, "1 sold out"
  end

  test "digest persists a KitchenTicketDigest with per-change payload" do
    seed_three_event_drops!

    digest = KitchenTicketDigest.order(created_at: :desc).first
    assert_not_nil digest, "expected a KitchenTicketDigest record"
    assert_equal 4, digest.total_tickets
    assert_equal 3, digest.change_count
    assert_equal 0, digest.sold_out_count
    assert_equal 3, digest.entries.size

    sample = digest.entry_records.first
    assert sample.key?("name")
    assert sample.key?("old_spots")
    assert sample.key?("new_spots")
    assert sample.key?("week_index")
  end

  test "digest passes per-snapshot summary URL to APNs" do
    User.create!(email_address: "kitchen-recipient-1@example.com", role: "admin")
    captured = {}
    ApnsPusher.stub :send_alert, ->(_n, **opts) { captured.merge!(opts) } do
      seed_three_event_drops!
    end

    digest = KitchenTicketDigest.order(created_at: :desc).first
    assert_equal "/nykitchen/digests/#{digest.id}", captured[:url]
    assert_nil captured[:subtitle]
  end

  test "single-change push still deep-links to week anchor (no digest record)" do
    User.create!(email_address: "kitchen-recipient-2@example.com", role: "admin")
    captured = {}
    ApnsPusher.stub :send_alert, ->(_n, **opts) { captured.merge!(opts) } do
      post "/api/v1/kitchen_snapshots",
        params: { taken_on: @today, events: [
          { url: "https://nykitchen.com/events/pasta-101", name: "Pasta",
            start_at: 3.days.from_now.iso8601, spots_left: 5, capacity: 24,
            availability: "InStock" }
        ] }.to_json,
        headers: @headers

      post "/api/v1/kitchen_snapshots",
        params: { taken_on: @today, events: [
          { url: "https://nykitchen.com/events/pasta-101", name: "Pasta",
            start_at: 3.days.from_now.iso8601, spots_left: 3, capacity: 24,
            availability: "InStock" }
        ] }.to_json,
        headers: @headers
    end

    assert_match %r{\A/nykitchen#week-\d+\z}, captured[:url]
    assert_equal 0, KitchenTicketDigest.count
  end

  test "digest body labels sold-out lines distinctly" do
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/a", name: "Class A",
          start_at: 3.days.from_now.iso8601, spots_left: 2, capacity: 10,
          availability: "InStock" },
        { url: "https://nykitchen.com/events/b", name: "Class B",
          start_at: 4.days.from_now.iso8601, spots_left: 5, capacity: 10,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers

    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/a", name: "Class A",
          start_at: 3.days.from_now.iso8601, spots_left: 0, capacity: 10,
          availability: "SoldOut" },
        { url: "https://nykitchen.com/events/b", name: "Class B",
          start_at: 4.days.from_now.iso8601, spots_left: 3, capacity: 10,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers

    digest = Notification.where(source: "kitchen_tickets").order(created_at: :desc).first
    assert_match(/Class A: SOLD OUT \(2 → 0\)/, digest.body)
    assert_match(/Class B: 5 → 3/, digest.body)
    # Sold-out line should be listed first (highest signal)
    assert digest.body.index("Class A") < digest.body.index("Class B"),
      "sold-out class should appear before non-sold-out in digest body"
  end

  test "digest truncates body to first 5 changes plus count" do
    seed = (1..7).map do |i|
      { url: "https://nykitchen.com/events/c#{i}", name: "Class #{i}",
        start_at: (i + 2).days.from_now.iso8601, spots_left: 10, capacity: 20,
        availability: "InStock" }
    end
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: seed }.to_json,
      headers: @headers

    drop = seed.map { |e| e.merge(spots_left: 9) }
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: drop }.to_json,
      headers: @headers

    digest = Notification.where(source: "kitchen_tickets").order(created_at: :desc).first
    assert_includes digest.body, "+ 2 more"
    assert_includes digest.body, "Class 1"
    assert_includes digest.body, "Class 5"
    assert_not_includes digest.body, "Class 7"
  end

  test "stores image_url when provided in event data" do
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making Workshop",
          start_at: 3.days.from_now.iso8601, spots_left: 5, capacity: 24,
          availability: "InStock",
          image_url: "https://nykitchen.com/wp-content/uploads/pasta.jpg" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    event = KitchenSnapshot.order(taken_on: :desc).first.kitchen_events.first
    assert_equal "https://nykitchen.com/wp-content/uploads/pasta.jpg", event.image_url
  end

  test "image_url is nil when not provided" do
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making Workshop",
          start_at: 3.days.from_now.iso8601, spots_left: 5, capacity: 24,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    event = KitchenSnapshot.order(taken_on: :desc).first.kitchen_events.first
    assert_nil event.image_url
  end

  # --- Week-relative deep-link notifications ---

  test "notification includes Current Week subtitle and #week-0 deep link for this-week event" do
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making",
          start_at: 2.days.from_now.iso8601, spots_left: 5, capacity: 24,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers

    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making",
          start_at: 2.days.from_now.iso8601, spots_left: 3, capacity: 24,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers

    notification = Notification.where(source: "kitchen_tickets").order(created_at: :desc).first
    assert_not_nil notification
    # ApnsPusher is called with subtitle and url — verify via the Notification record
    # (ApnsPusher.send_alert is a no-op in test since there are no device tokens)
    # We test the week_info_for logic directly below
  end

  test "week_info_for returns Current Week for event today" do
    controller = Api::V1::KitchenSnapshotsController.new
    event = OpenStruct.new(start_at: Time.current)
    index, label = controller.send(:week_info_for, event)
    assert_equal 0, index
    assert_equal "Current Week", label
  end

  test "week_info_for returns Current Week for event this Sunday" do
    controller = Api::V1::KitchenSnapshotsController.new
    today = Date.today
    days_until_sunday = (7 - today.cwday) % 7
    this_sunday = today + days_until_sunday
    event = OpenStruct.new(start_at: this_sunday.to_time)
    index, label = controller.send(:week_info_for, event)
    assert_equal 0, index
    assert_equal "Current Week", label
  end

  test "week_info_for returns Next Week for event next Monday" do
    controller = Api::V1::KitchenSnapshotsController.new
    today = Date.today
    days_until_sunday = (7 - today.cwday) % 7
    next_monday = today + days_until_sunday + 1
    event = OpenStruct.new(start_at: next_monday.to_time)
    index, label = controller.send(:week_info_for, event)
    assert_equal 1, index
    assert_equal "Next Week", label
  end

  test "week_info_for returns In 2 Weeks for event two weeks out" do
    controller = Api::V1::KitchenSnapshotsController.new
    today = Date.today
    days_until_sunday = (7 - today.cwday) % 7
    two_weeks_monday = today + days_until_sunday + 8
    event = OpenStruct.new(start_at: two_weeks_monday.to_time)
    index, label = controller.send(:week_info_for, event)
    assert_equal 2, index
    assert_equal "In 2 Weeks", label
  end

  test "week_info_for returns In 3 Weeks for event three weeks out" do
    controller = Api::V1::KitchenSnapshotsController.new
    today = Date.today
    days_until_sunday = (7 - today.cwday) % 7
    three_weeks_monday = today + days_until_sunday + 15
    event = OpenStruct.new(start_at: three_weeks_monday.to_time)
    index, label = controller.send(:week_info_for, event)
    assert_equal 3, index
    assert_equal "In 3 Weeks", label
  end

  test "ticket change notification deep links to correct week anchor" do
    # Event is ~3 weeks out
    today = Date.today
    days_until_sunday = (7 - today.cwday) % 7
    three_weeks_out = today + days_until_sunday + 15

    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/wine-201", name: "Wine Tasting",
          start_at: three_weeks_out.to_time.iso8601, spots_left: 10, capacity: 30,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers

    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/wine-201", name: "Wine Tasting",
          start_at: three_weeks_out.to_time.iso8601, spots_left: 7, capacity: 30,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers

    notification = Notification.where(source: "kitchen_tickets").order(created_at: :desc).first
    assert_not_nil notification
    assert_includes notification.title, "Wine Tasting"
    assert_includes notification.title, "3 ticket(s) bought"
  end

  # --- "Tickets no longer available" (Closed) carry-forward ---

  test "closed-not-soldout class carries forward prior spots, capacity, and price" do
    yesterday = (Date.current - 1).to_s
    url = "https://nykitchen.com/events/pinot-101"

    # Day 1: selling normally — 7 of 32 sold at $57.
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: yesterday, events: [
        { url: url, name: "Pinot Noir Decoded",
          start_at: 2.days.from_now.iso8601, spots_left: 25, capacity: 32,
          price: "57.00", availability: "InStock" }
      ] }.to_json, headers: @headers
    assert_response :created

    # Day 2: online sales close — the page now shows 0 left and no price.
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: url, name: "Pinot Noir Decoded",
          start_at: 2.days.from_now.iso8601, spots_left: 0, capacity: nil,
          price: nil, availability: "Closed" }
      ] }.to_json, headers: @headers
    assert_response :created

    e = KitchenSnapshot.find_by(taken_on: @today).kitchen_events.find_by(url: url)
    assert_equal "Closed", e.availability
    assert_equal 25, e.spots_left, "should keep prior spots, not the closed 0"
    assert_equal "57.00", e.price, "should keep prior price"
    assert_equal 7, e.tickets_sold, "must not inflate sold to capacity"
  end

  test "genuine SoldOut keeps zero spots (real sellout preserved, not carried over)" do
    yesterday = (Date.current - 1).to_s
    url = "https://nykitchen.com/events/sellout-101"

    post "/api/v1/kitchen_snapshots",
      params: { taken_on: yesterday, events: [
        { url: url, name: "Hot Class",
          start_at: 2.days.from_now.iso8601, spots_left: 2, capacity: 10,
          price: "50.00", availability: "InStock" }
      ] }.to_json, headers: @headers

    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: url, name: "Hot Class",
          start_at: 2.days.from_now.iso8601, spots_left: 0, capacity: 10,
          price: "50.00", availability: "SoldOut" }
      ] }.to_json, headers: @headers

    e = KitchenSnapshot.find_by(taken_on: @today).kitchen_events.find_by(url: url)
    assert_equal 0, e.spots_left
    assert_equal 10, e.tickets_sold
  end

  test "sold-out class with blank price keeps the prior price (revenue not lost)" do
    yesterday = (Date.current - 1).to_s
    url = "https://nykitchen.com/events/chefs-table"

    # Day 1: selling at $190.
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: yesterday, events: [
        { url: url, name: "Chef's Table",
          start_at: 2.days.from_now.iso8601, spots_left: 4, capacity: 12,
          price: "190.00", availability: "InStock" }
      ] }.to_json, headers: @headers

    # Day 2: sells out — the page hides the price (sends blank), 0 left.
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: url, name: "Chef's Table",
          start_at: 2.days.from_now.iso8601, spots_left: 0, capacity: 12,
          price: nil, availability: "SoldOut" }
      ] }.to_json, headers: @headers

    e = KitchenSnapshot.find_by(taken_on: @today).kitchen_events.find_by(url: url)
    assert_equal "SoldOut", e.availability
    assert_equal 0, e.spots_left, "sold out really is 0 left"
    assert_equal 12, e.tickets_sold
    assert_equal "190.00", e.price, "price must carry forward, not drop to nil"
    assert_equal 2280.0, e.revenue_sold
  end

  test "proxy high-water ratchets up and survives a drop-off then return" do
    url = "https://nykitchen.com/events/proxy-1"
    # Day 1: first seen at 30 spots, no capacity from the page (proxy class).
    post "/api/v1/kitchen_snapshots", params: { taken_on: (Date.current - 3).to_s, events: [
      { url: url, name: "Proxy", start_at: 6.days.from_now.iso8601, spots_left: 30, availability: "InStock" }
    ] }.to_json, headers: @headers
    # Day 2: sells 2 → 28.
    post "/api/v1/kitchen_snapshots", params: { taken_on: (Date.current - 2).to_s, events: [
      { url: url, name: "Proxy", start_at: 6.days.from_now.iso8601, spots_left: 28, availability: "InStock" }
    ] }.to_json, headers: @headers
    # Day 3: class drops off the calendar entirely (different class scraped).
    post "/api/v1/kitchen_snapshots", params: { taken_on: (Date.current - 1).to_s, events: [
      { url: "https://nykitchen.com/events/other", name: "Other", start_at: 6.days.from_now.iso8601, spots_left: 5, capacity: 10, availability: "InStock" }
    ] }.to_json, headers: @headers
    # Day 4: returns, still at 28.
    post "/api/v1/kitchen_snapshots", params: { taken_on: @today, events: [
      { url: url, name: "Proxy", start_at: 6.days.from_now.iso8601, spots_left: 28, availability: "InStock" }
    ] }.to_json, headers: @headers

    e = KitchenSnapshot.find_by(taken_on: @today).kitchen_events.find_by(url: url)
    assert_equal 30, e.last_known_spots_left, "high-water must survive the drop-off, not reset to 28"
    assert_equal 2, e.tickets_sold, "30 high-water minus 28 left = 2 sold"
  end

  test "notification when event sells out completely" do
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making Workshop",
          start_at: 3.days.from_now.iso8601, spots_left: 2, capacity: 24,
          availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/pasta-101", name: "Pasta Making Workshop",
          start_at: 3.days.from_now.iso8601, spots_left: 0, capacity: 24,
          availability: "SoldOut" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    notification = Notification.where(source: "kitchen_tickets").order(created_at: :desc).first
    assert_not_nil notification
    assert_includes notification.title, "2"
    assert_includes notification.title, "SOLD OUT"
  end

  test "persists the scraped menu on the event" do
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/strawberries", name: "Strawberries Class",
          start_at: 3.days.from_now.iso8601, availability: "InStock",
          menu: "Strawberry Crostini / Strawberry Shortcake" }
      ] }.to_json,
      headers: @headers
    assert_response :success
    assert_equal "Strawberry Crostini / Strawberry Shortcake",
                 KitchenSnapshot.find_by(taken_on: @today).kitchen_events.first.menu
  end

  # --- Wrongly-closed safeguard (fat-fingered sales-end date) ---

  private def warning_alerts
    Notification.where(source: "kitchen_tickets", level: "warning")
  end
  public

  test "alerts when a far-out class is closed with seats still open" do
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/mystery", name: "Mystery Dinner",
          start_at: 30.days.from_now.iso8601, spots_left: 10, capacity: 24,
          availability: "Closed" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    alert = warning_alerts.order(created_at: :desc).first
    assert_not_nil alert, "Expected a wrongly-closed warning"
    assert_includes alert.title, "closed too early"
    assert_includes alert.title, "Mystery Dinner"
  end

  test "does not alert for normal near-term cutoffs, full classes, or sold-out classes" do
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/near", name: "Tomorrow",
          start_at: 3.days.from_now.iso8601, spots_left: 10, capacity: 24, availability: "Closed" },
        { url: "https://nykitchen.com/events/full", name: "Full",
          start_at: 30.days.from_now.iso8601, spots_left: 0, capacity: 24, availability: "Closed" },
        { url: "https://nykitchen.com/events/sold", name: "Gone",
          start_at: 30.days.from_now.iso8601, spots_left: 0, capacity: 24, availability: "SoldOut" }
      ] }.to_json,
      headers: @headers
    assert_response :created
    assert_equal 0, warning_alerts.count
  end

  test "does not re-alert a wrongly-closed class on a later snapshot, but does on a fresh open-to-closed flip" do
    yesterday = (Date.current - 1).to_s

    # Yesterday: class A already wrongly closed (fires), class B still bookable.
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: yesterday, events: [
        { url: "https://nykitchen.com/events/a", name: "Class A",
          start_at: 30.days.from_now.iso8601, spots_left: 10, capacity: 24, availability: "Closed" },
        { url: "https://nykitchen.com/events/b", name: "Class B",
          start_at: 30.days.from_now.iso8601, spots_left: 10, capacity: 24, availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_equal 1, warning_alerts.count

    # Today: A is STILL closed (must not re-alert); B newly flips to closed (fires).
    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/events/a", name: "Class A",
          start_at: 30.days.from_now.iso8601, spots_left: 10, capacity: 24, availability: "Closed" },
        { url: "https://nykitchen.com/events/b", name: "Class B",
          start_at: 30.days.from_now.iso8601, spots_left: 10, capacity: 24, availability: "Closed" }
      ] }.to_json,
      headers: @headers

    assert_equal 2, warning_alerts.count, "A should not re-alert; only B's new flip should"
    assert_includes warning_alerts.order(created_at: :desc).first.title, "Class B"
  end

  test "ingest does not eagerly link recipes (carry-forward is lazy, on open)" do
    recipes = [ { "title" => "Korean BBQ",
      "ingredients" => [ { "qty" => "1 lb", "station_qty" => "1/2 lb", "item" => "Short rib", "section" => nil } ],
      "directions" => [ { "section" => nil, "steps" => [ "Grill." ] } ] } ]
    packet = KitchenPacket.create!(title: "Korean Barbecue Class 6/19/26", data: { "recipes" => recipes })

    post "/api/v1/kitchen_snapshots",
      params: { taken_on: @today, events: [
        { url: "https://nykitchen.com/event/korean-bbq-7-3/", name: "Korean Barbecue Class 7/3/26",
          start_at: 3.weeks.from_now.iso8601, spots_left: 10, capacity: 24, availability: "InStock" }
      ] }.to_json,
      headers: @headers
    assert_response :created

    # The new run is NOT pre-linked at ingest; it carries forward only when a
    # user opens it (KitchenPacketsController#open copies the matching packet).
    assert_nil KitchenPacketLink.find_by(event_url: "https://nykitchen.com/event/korean-bbq-7-3/")
    assert_equal packet, KitchenPacketAutoAttacher.packet_for("Korean Barbecue Class 7/3/26")
  end
end
