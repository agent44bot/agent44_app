require "test_helper"

class KitchenPacketAutoAttacherTest < ActiveSupport::TestCase
  RECIPES = [ { "title" => "Korean BBQ",
    "ingredients" => [ { "qty" => "1 lb", "station_qty" => "1/2 lb", "item" => "Short rib", "section" => nil } ],
    "directions" => [ { "section" => nil, "steps" => [ "Grill." ] } ] } ].freeze

  def packet(title)
    KitchenPacket.create!(title: title, data: { "recipes" => RECIPES })
  end

  def snapshot_with(*events)
    snap = KitchenSnapshot.create!(taken_on: Date.current)
    events.each_with_index do |(name, url, when_at), i|
      snap.kitchen_events.create!(name: name, url: url, start_at: when_at || 2.weeks.from_now,
                                  availability: "InStock")
    end
    snap
  end

  test "curriculum_key strips dates, punctuation, and generic words" do
    k1 = KitchenPacketAutoAttacher.curriculum_key("Korean Barbecue Class 6/19/26")
    k2 = KitchenPacketAutoAttacher.curriculum_key("Korean Barbecue Class 6/27/26")
    assert_equal k1, k2
    assert_equal Set.new(%w[korean barbecue]), k1
  end

  test "curriculum_key is nil for too-generic names" do
    assert_nil KitchenPacketAutoAttacher.curriculum_key("Cooking Class")
    assert_nil KitchenPacketAutoAttacher.curriculum_key("Private Event")
  end

  test "attach_forward links future same-curriculum runs and marks them auto" do
    h = packet("Korean Barbecue Class 6/19/26")
    h.attach_to!("https://nyk/event/korean-bbq-6-19/") # manual on the first run
    snapshot_with(
      [ "Korean Barbecue Class 6/19/26", "https://nyk/event/korean-bbq-6-19/" ],
      [ "Korean Barbecue Class 7/3/26",  "https://nyk/event/korean-bbq-7-3/" ],
      [ "Sourdough Basics 7/5/26",       "https://nyk/event/sourdough-7-5/" ]
    )

    linked = KitchenPacketAutoAttacher.attach_forward(h)
    assert_equal 1, linked
    sibling = KitchenPacketLink.find_by(event_url: "https://nyk/event/korean-bbq-7-3/")
    assert_equal h, sibling.kitchen_packet
    assert sibling.auto, "auto-linked sibling should be flagged auto"
    assert_nil KitchenPacketLink.find_by(event_url: "https://nyk/event/sourdough-7-5/")
  end

  test "attach_forward never overwrites an existing (manual) link" do
    korean = packet("Korean Barbecue Class")
    other  = packet("Korean Barbecue Class") # a second, different packet
    snapshot_with([ "Korean Barbecue Class 7/3/26", "https://nyk/event/korean-bbq-7-3/" ])
    other.attach_to!("https://nyk/event/korean-bbq-7-3/") # manual choice stays

    KitchenPacketAutoAttacher.attach_forward(korean)
    assert_equal other, KitchenPacketLink.find_by(event_url: "https://nyk/event/korean-bbq-7-3/").kitchen_packet
  end

  test "attach_forward skips past classes" do
    h = packet("Korean Barbecue Class")
    snapshot_with([ "Korean Barbecue Class 1/1/26", "https://nyk/event/korean-bbq-past/", 2.weeks.ago ])
    assert_equal 0, KitchenPacketAutoAttacher.attach_forward(h)
  end

  test "attach_forward does nothing for a too-generic packet title" do
    h = packet("Cooking Class")
    snapshot_with([ "Cooking Class 7/3/26", "https://nyk/event/cooking-7-3/" ])
    assert_equal 0, KitchenPacketAutoAttacher.attach_forward(h)
  end

  test "run_for_snapshot links new future runs to a matching existing packet" do
    h = packet("Korean Barbecue Class 6/19/26")
    snap = snapshot_with(
      [ "Korean Barbecue Class 7/3/26", "https://nyk/event/korean-bbq-7-3/" ],
      [ "Knife Skills 7/4/26",          "https://nyk/event/knife-7-4/" ]
    )

    linked = KitchenPacketAutoAttacher.run_for_snapshot(snap)
    assert_equal 1, linked
    assert_equal h, KitchenPacketLink.find_by(event_url: "https://nyk/event/korean-bbq-7-3/")&.kitchen_packet
    assert_nil KitchenPacketLink.find_by(event_url: "https://nyk/event/knife-7-4/")
  end

  test "run_for_snapshot leaves already-linked classes alone" do
    h1 = packet("Korean Barbecue Class")
    h2 = packet("Korean Barbecue Class")
    snap = snapshot_with([ "Korean Barbecue Class 7/3/26", "https://nyk/event/korean-bbq-7-3/" ])
    h2.attach_to!("https://nyk/event/korean-bbq-7-3/") # manual

    KitchenPacketAutoAttacher.run_for_snapshot(snap)
    assert_equal h2, KitchenPacketLink.find_by(event_url: "https://nyk/event/korean-bbq-7-3/").kitchen_packet
  end
end
