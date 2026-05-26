require "test_helper"

class KitchenAi::MorningPromptTest < ActiveSupport::TestCase
  def event(snap, **attrs)
    snap.kitchen_events.create!({ url: "https://nykitchen.test/#{SecureRandom.hex(3)}" }.merge(attrs))
  end

  test "surfaces the class closest to selling out, even if a sooner class has more seats" do
    snap = KitchenSnapshot.create!(taken_on: Date.current)
    event(snap, name: "Soon But Open", availability: "InStock", spots_left: 3, start_at: 1.day.from_now)
    event(snap, name: "Almost Gone",   availability: "InStock", spots_left: 1, start_at: 5.days.from_now)

    q = KitchenAi::MorningPrompt.question
    assert_match "Almost Gone", q            # fewest seats wins over the sooner-but-roomier class
    assert_match "1 seat", q
  end

  test "ties on seat count break to the soonest class" do
    snap = KitchenSnapshot.create!(taken_on: Date.current)
    event(snap, name: "Later One Seat",  availability: "InStock", spots_left: 1, start_at: 5.days.from_now)
    event(snap, name: "Sooner One Seat", availability: "InStock", spots_left: 1, start_at: 2.days.from_now)

    assert_match "Sooner One Seat", KitchenAi::MorningPrompt.question
  end

  test "falls back to a sold-out nudge when nothing is nearly full" do
    snap = KitchenSnapshot.create!(taken_on: Date.current)
    event(snap, name: "Gnocchi", availability: "SoldOut", spots_left: 0,  start_at: 3.days.from_now)
    event(snap, name: "Bread",   availability: "InStock", spots_left: 20, start_at: 4.days.from_now)

    q = KitchenAi::MorningPrompt.question
    assert_match "sold out", q
    assert_match "1 upcoming", q
  end

  test "rotates a generic question, stable within a calendar day" do
    snap = KitchenSnapshot.create!(taken_on: Date.current)
    event(snap, name: "Bread", availability: "InStock", spots_left: 20, start_at: 4.days.from_now)

    day  = Date.new(2026, 5, 26)
    q1   = KitchenAi::MorningPrompt.question(today: day)
    q2   = KitchenAi::MorningPrompt.question(today: day)
    qnxt = KitchenAi::MorningPrompt.question(today: day + 1)

    assert_includes KitchenAi::MorningPrompt::FALLBACKS, q1
    assert_equal q1, q2                       # same day → same question
    refute_equal q1, qnxt                     # next day → rotates
  end

  test "no snapshot yields a fallback (never raises)" do
    assert_includes KitchenAi::MorningPrompt::FALLBACKS, KitchenAi::MorningPrompt.question
  end
end
