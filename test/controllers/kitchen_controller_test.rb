require "test_helper"

class KitchenControllerTest < ActionDispatch::IntegrationTest
  setup do
    @today = Date.today
    @snapshot = KitchenSnapshot.create!(taken_on: @today)
  end

  test "week headers show availability bar with correct segments" do
    # Create events this week: 2 available, 1 sold out, 1 limited
    this_week = 2.days.from_now
    create_event("Pasta 101", this_week, "InStock")
    create_event("Wine 201", this_week + 1.hour, "InStock")
    create_event("Cheese Class", this_week + 2.hours, "SoldOut")
    create_event("Baking Basics", this_week + 3.hours, "Limited")

    get nykitchen_path
    assert_response :success

    # The bar should have all three segments
    assert_select "div.bg-red-500"    # sold out segment
    assert_select "div.bg-amber-500"  # limited segment
    assert_select "div.bg-green-500"  # available segment
  end

  test "week with all available events shows only green bar" do
    next_monday = @today + ((7 - @today.cwday) % 7) + 1
    create_event("Event A", next_monday.to_time + 10.hours, "InStock")
    create_event("Event B", next_monday.to_time + 14.hours, "InStock")

    get nykitchen_path
    assert_response :success

    # Find the week section containing these events
    assert_select "section[id^='week-']" do |sections|
      next_week_section = sections.find { |s| s.text.include?("Event A") }
      assert next_week_section, "Expected a week section containing the events"
      assert_select next_week_section, "div.bg-green-500"
      assert_select next_week_section, "div.bg-red-500", count: 0
      assert_select next_week_section, "div.bg-amber-500", count: 0
    end
  end

  test "week with all sold out events shows only red bar" do
    next_monday = @today + ((7 - @today.cwday) % 7) + 1
    create_event("Sold A", next_monday.to_time + 10.hours, "SoldOut")
    create_event("Sold B", next_monday.to_time + 14.hours, "SoldOut")
    create_event("Closed C", next_monday.to_time + 16.hours, "Closed")

    get nykitchen_path
    assert_response :success

    assert_select "section[id^='week-']" do |sections|
      section = sections.find { |s| s.text.include?("Sold A") }
      assert section, "Expected a week section with sold out events"
      assert_select section, "div.bg-red-500"
      assert_select section, "div.bg-green-500", count: 0
    end
  end

  test "availability bar percentages reflect event counts" do
    # 3 events: 1 sold out (33.3%), 2 available (66.7%)
    this_week = 2.days.from_now
    create_event("Available 1", this_week, "InStock")
    create_event("Available 2", this_week + 1.hour, "InStock")
    create_event("Gone", this_week + 2.hours, "SoldOut")

    get nykitchen_path
    assert_response :success

    assert_select "div.bg-red-500[title='1 sold out / closed']"
    assert_select "div.bg-green-500[title='2 available']"
  end

  test "events with empty availability show as gray not green or red" do
    this_week = 2.days.from_now
    create_event("Sold Out Class", this_week, "SoldOut")
    create_event("Private Event", this_week + 1.hour, "")  # empty = "other"

    get nykitchen_path
    assert_response :success

    assert_select "section[id^='week-']" do |sections|
      section = sections.find { |s| s.text.include?("Private Event") }
      assert section
      assert_select section, "div.bg-green-500", count: 0, message: "Empty availability should not show as green"
      assert_select section, "div.bg-gray-500[title='1 unknown']"
      assert_select section, "div.bg-red-500[title='1 sold out / closed']"
    end
  end

  test "each week section has an id for deep linking" do
    # Pin to a Tuesday so week 0 spans Tue–Sun and week 1 starts the next
    # Monday. Otherwise late-week runs (e.g. Saturday) push 2.days.from_now
    # past Sunday, leaving week 0 empty and the view skipping its section.
    travel_to Time.zone.local(2026, 6, 16, 9, 0) do
      create_event("This Week Event", 1.day.from_now, "InStock")
      create_event("Next Week Event", 7.days.from_now, "InStock")

      get nykitchen_path
      assert_response :success

      assert_select "section#week-0"
      assert_select "section#week-1"
    end
  end

  test "digest summary page renders totals and per-event old → new spots" do
    digest = @snapshot.kitchen_ticket_digests.create!(
      total_tickets: 5,
      sold_out_count: 1,
      change_count: 2,
      entries: [
        { url: "https://nykitchen.com/events/pasta", name: "Pasta Making",
          start_at: 3.days.from_now.iso8601, instructor: "Chef Lora", price: "85",
          old_spots: 4, new_spots: 0, tickets_bought: 4, sold_out: true,
          week_index: 0, week_label: "Current Week" },
        { url: "https://nykitchen.com/events/wine", name: "Wine Tasting",
          start_at: 10.days.from_now.iso8601, instructor: nil, price: nil,
          old_spots: 12, new_spots: 11, tickets_bought: 1, sold_out: false,
          week_index: 1, week_label: "Next Week" }
      ]
    )

    get nyk_digest_path(digest)
    assert_response :success

    # Stat tiles
    assert_match(/5/, response.body)   # tickets total
    assert_match(/2/, response.body)   # change count
    assert_match(/1/, response.body)   # sold out count

    # Week sections
    assert_match("Current Week", response.body)
    assert_match("Next Week", response.body)

    # Per-event details
    assert_match("Pasta Making", response.body)
    assert_match("Wine Tasting", response.body)
    assert_match(/4 .*?→.*?0/m, response.body)
    assert_match(/12 .*?→.*?11/m, response.body)
    assert_match("SOLD OUT", response.body)
  end

  test "digest summary page returns 404 for unknown id" do
    get nyk_digest_path(id: 999_999)
    assert_response :not_found
  end

  private

  def create_event(name, start_at, availability)
    @snapshot.kitchen_events.create!(
      url: "https://nykitchen.com/events/#{name.parameterize}",
      name: name,
      start_at: start_at,
      availability: availability
    )
  end
end
