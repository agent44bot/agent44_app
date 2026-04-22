require "test_helper"

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
end
