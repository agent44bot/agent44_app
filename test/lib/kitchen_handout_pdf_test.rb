require "test_helper"

class KitchenHandoutPdfTest < ActiveSupport::TestCase
  def handout(recipes)
    KitchenHandout.new(title: "Packet", station_label: "Single station",
                       data: { "recipes" => recipes })
  end

  test "renders a multi-page PDF: each recipe at full then station scale" do
    h = handout([
      { "title" => "Fresh Pasta",
        "ingredients" => [ { "qty" => "2½ c", "station_qty" => "1¼ c", "item" => "Flour", "section" => nil } ],
        "directions" => [ { "section" => nil, "steps" => [ "Mix." ] } ] },
      { "title" => "Sauce",
        "ingredients" => [ { "qty" => "2 T", "station_qty" => "1 T", "item" => "Butter", "section" => nil } ],
        "directions" => [ { "section" => nil, "steps" => [ "Melt." ] } ] }
    ])
    bytes = KitchenHandoutPdf.new(h).render
    assert bytes.start_with?("%PDF"), "PDF header"
    # 2 recipes x (full + station) = 4 content pages.
    pages = bytes.scan(%r{/Type\s*/Page[^s]}).size
    assert_equal 4, pages
  end

  test "ASCII-ifies unicode fractions so AFM fonts never raise" do
    h = handout([
      { "title" => "Thirds", "ingredients" => [
        { "qty" => "⅓ c", "station_qty" => "⅙ c", "item" => "Sugar", "section" => nil }
      ], "directions" => [] }
    ])
    # The real assertion is that this does not raise on the ⅓/⅙ glyphs.
    assert KitchenHandoutPdf.new(h).render.start_with?("%PDF")
  end

  test "empty handout still renders a valid PDF" do
    assert KitchenHandoutPdf.new(handout([])).render.start_with?("%PDF")
  end
end
