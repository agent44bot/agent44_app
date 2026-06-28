require "test_helper"

class KitchenPacketAutoAttacherTest < ActiveSupport::TestCase
  RECIPES = [ { "title" => "Korean BBQ",
    "ingredients" => [ { "qty" => "1 lb", "station_qty" => "1/2 lb", "item" => "Short rib", "section" => nil } ],
    "directions" => [ { "section" => nil, "steps" => [ "Grill." ] } ] } ].freeze

  def packet(title)
    KitchenPacket.create!(title: title, data: { "recipes" => RECIPES })
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

  test "packet_for finds the matching-curriculum packet for a class name" do
    korean = packet("Korean Barbecue Class 6/19/26")
    packet("Sourdough Basics 7/5/26")
    assert_equal korean, KitchenPacketAutoAttacher.packet_for("Korean Barbecue Class 7/3/26")
  end

  test "packet_for returns the most recently edited packet of a curriculum" do
    older = packet("Korean Barbecue Class 6/19/26")
    newer = packet("Korean Barbecue Class 6/26/26")
    # Make `older` the most recently touched so "latest edited" wins regardless
    # of insert order.
    older.touch
    assert_equal older, KitchenPacketAutoAttacher.packet_for("Korean Barbecue Class 7/3/26")
    newer.touch
    assert_equal newer, KitchenPacketAutoAttacher.packet_for("Korean Barbecue Class 7/3/26")
  end

  test "packet_for is nil for a too-generic class name" do
    packet("Cooking Class")
    assert_nil KitchenPacketAutoAttacher.packet_for("Cooking Class 7/3/26")
  end

  test "packet_for is nil when no curriculum matches" do
    packet("Korean Barbecue Class 6/19/26")
    assert_nil KitchenPacketAutoAttacher.packet_for("Knife Skills 7/4/26")
  end
end
