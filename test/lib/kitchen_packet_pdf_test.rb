require "test_helper"

class KitchenPacketPdfTest < ActiveSupport::TestCase
  def packet(recipes)
    KitchenPacket.new(title: "Packet", station_label: "Single station",
                       data: { "recipes" => recipes })
  end

  test "renders a multi-page PDF: each recipe at full then station scale" do
    h = packet([
      { "title" => "Fresh Pasta",
        "ingredients" => [ { "qty" => "2½ c", "station_qty" => "1¼ c", "item" => "Flour", "section" => nil } ],
        "directions" => [ { "section" => nil, "steps" => [ "Mix." ] } ] },
      { "title" => "Sauce",
        "ingredients" => [ { "qty" => "2 T", "station_qty" => "1 T", "item" => "Butter", "section" => nil } ],
        "directions" => [ { "section" => nil, "steps" => [ "Melt." ] } ] }
    ])
    bytes = KitchenPacketPdf.new(h).render
    assert bytes.start_with?("%PDF"), "PDF header"
    # 2 recipes x (full + station) = 4 content pages.
    pages = bytes.scan(%r{/Type\s*/Page[^s]}).size
    assert_equal 4, pages
  end

  test "ASCII-ifies unicode fractions so AFM fonts never raise" do
    h = packet([
      { "title" => "Thirds", "ingredients" => [
        { "qty" => "⅓ c", "station_qty" => "⅙ c", "item" => "Sugar", "section" => nil }
      ], "directions" => [] }
    ])
    # The real assertion is that this does not raise on the ⅓/⅙ glyphs.
    assert KitchenPacketPdf.new(h).render.start_with?("%PDF")
  end

  test "empty packet still renders a valid PDF" do
    assert KitchenPacketPdf.new(packet([])).render.start_with?("%PDF")
  end

  # Every page is labeled: the full-quantity pass is "Dual station" (station
  # amount is half), the scaled pass is the packet's station_label. (PDF text
  # is subset-TTF glyphs, so we can't grep the bytes; this pins the label and
  # the page count proves both passes still render.)
  test "full pages are labeled Dual station and both passes render" do
    assert_equal "Dual station", KitchenPacketPdf::DUAL_STATION_LABEL
    h = packet([
      { "title" => "Rice",
        "ingredients" => [ { "qty" => "4 c", "station_qty" => "2 c", "item" => "Rice", "section" => nil } ],
        "directions" => [ { "section" => nil, "steps" => [ "Cook." ] } ] }
    ])
    bytes = KitchenPacketPdf.new(h).render
    # 1 recipe x (dual + single) = 2 pages.
    assert_equal 2, bytes.scan(%r{/Type\s*/Page[^s]}).size
  end
end
