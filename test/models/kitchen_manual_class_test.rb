require "test_helper"

class KitchenManualClassTest < ActiveSupport::TestCase
  test "upcoming includes future and excludes past, using end_at when present" do
    future = KitchenManualClass.create!(name: "Kids Camp", start_at: 2.days.from_now)
    past   = KitchenManualClass.create!(name: "Old Camp", start_at: 3.days.ago)
    # Started yesterday but runs through tomorrow -> still upcoming via end_at.
    ongoing = KitchenManualClass.create!(name: "Week Camp", start_at: 1.day.ago, end_at: 1.day.from_now)

    up = KitchenManualClass.upcoming
    assert_includes up, future
    assert_includes up, ongoing
    refute_includes up, past
  end

  test "requires a name and a start_at" do
    assert_not KitchenManualClass.new(start_at: Time.current).valid?
    assert_not KitchenManualClass.new(name: "x").valid?
  end

  test "venue_label falls back to the default" do
    assert_equal KitchenManualClass::DEFAULT_VENUE, KitchenManualClass.new.venue_label
    assert_equal "Barn", KitchenManualClass.new(venue: "Barn").venue_label
  end

  test "packet_url is a stable synthetic key tied to the row" do
    mc = KitchenManualClass.create!(name: "Camp", start_at: 1.day.from_now)
    assert_equal "manual-#{mc.id}", mc.packet_url
  end
end
