require "test_helper"

class KitchenPacketPdfTest < ActiveSupport::TestCase
  def packet(recipes)
    KitchenPacket.new(title: "Packet", station_label: "Single",
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

  test "directions are numbered continuously, section headers do not take a number" do
    recipe = { "title" => "Two Part",
      "ingredients" => [],
      "directions" => [
        { "section" => "Prep", "steps" => [ "Chop.", "Measure." ] },
        { "section" => "Cook", "steps" => [ "Heat.", "Stir." ] }
      ] }
    rows = KitchenPacketPdf.new(packet([ recipe ])).send(:direction_rows, recipe)
    numbers = rows.reject { |r| r.first.is_a?(Hash) }.map(&:first)
    assert_equal %w[1. 2. 3. 4.], numbers, "steps numbered continuously across sections"
    headers = rows.select { |r| r.first.is_a?(Hash) }
    assert_equal 2, headers.size, "each section renders one spanning header row"
  end

  test "a long recipe still fits one page per pass (auto-fit, no spillover)" do
    ingredients = (1..30).map { |i| { "qty" => "#{i} c", "station_qty" => "#{i} c", "item" => "Item #{i}", "section" => nil } }
    steps = (1..20).map { |i| "Do step number #{i}, which has a reasonably long sentence to force wrapping." }
    h = packet([ { "title" => "Big Recipe", "ingredients" => ingredients,
                   "directions" => [ { "section" => nil, "steps" => steps } ] } ])
    bytes = KitchenPacketPdf.new(h).render
    assert_equal 2, bytes.scan(%r{/Type\s*/Page[^s]}).size, "one page for full + one for station, no overflow pages"
  end

  # Every page is labeled: the full-quantity pass is "Double" (station amount
  # is half), the scaled pass is the packet's station_label. (PDF text is
  # subset-TTF glyphs, so we can't grep the bytes; this pins the label and
  # the page count proves both passes still render.)
  test "full pages are labeled Double and both passes render" do
    assert_equal "Double", KitchenPacketPdf::DUAL_STATION_LABEL
    h = packet([
      { "title" => "Rice",
        "ingredients" => [ { "qty" => "4 c", "station_qty" => "2 c", "item" => "Rice", "section" => nil } ],
        "directions" => [ { "section" => nil, "steps" => [ "Cook." ] } ] }
    ])
    bytes = KitchenPacketPdf.new(h).render
    # 1 recipe x (dual + single) = 2 pages.
    assert_equal 2, bytes.scan(%r{/Type\s*/Page[^s]}).size
  end

  test "title size and ingredient column follow the packet's layout settings" do
    recipe = { "title" => "Fresh Pasta",
               "ingredients" => [ { "qty" => "2½ c", "station_qty" => "1¼ c", "item" => "All-purpose flour", "section" => nil } ],
               "directions" => [ { "section" => nil, "steps" => [ "Mix." ] } ] }
    normal = packet([ recipe ])
    big = packet([ recipe ])
    big.layout = { "title_size" => "xlarge", "ingredient_width" => "wide" }
    assert_equal 24, normal.title_size_pt
    assert_equal 36, big.title_size_pt
    assert_in_delta 0.50, big.ingredient_width_ratio, 0.001
    # Both still render a valid two-page PDF.
    [ normal, big ].each { |h| assert_equal 2, KitchenPacketPdf.new(h).render.scan(%r{/Type\s*/Page[^s]}).size }
  end

  test "layout rejects values outside the menus" do
    h = packet([])
    h.layout = { "title_size" => "gigantic", "ingredient_width" => "huge", "junk" => 1 }
    assert_equal({ "title_size" => "normal", "ingredient_width" => "normal" }, h.layout)
  end

  test "a parenthetical like (~300 g) never splits mid-group" do
    pdf = KitchenPacketPdf.new(packet([]))
    doc = pdf.send(:new_document)
    rows = [ [ "2 ½ c", "All-purpose flour (~300 g)" ], [ "1", "Egg (large)" ] ]
    # Column too narrow for the first item at 12pt: break before the parenthetical.
    pdf.send(:keep_parentheticals, doc, rows, 90, 12)
    assert_equal "All-purpose flour\n(~300 g)", rows[0][1]
    assert_equal "Egg (large)", rows[1][1]
    # Plenty of room: left alone.
    rows = [ [ "2 ½ c", "All-purpose flour (~300 g)" ] ]
    pdf.send(:keep_parentheticals, doc, rows, 400, 12)
    assert_equal "All-purpose flour (~300 g)", rows[0][1]
  end

  test "headcount is not printed on the handout" do
    recipe = { "title" => "Rice", "headcount" => 24,
               "ingredients" => [ { "qty" => "4 c", "station_qty" => "2 c", "item" => "Rice", "section" => nil } ],
               "directions" => [ { "section" => nil, "steps" => [ "Cook." ] } ] }
    doc = Prawn::Document.new
    texts = []
    doc.define_singleton_method(:text) { |str, *_| texts << str }
    doc.define_singleton_method(:table) { |*_| nil }
    doc.define_singleton_method(:make_table) { |*_| Struct.new(:height).new(10) }
    pdf = KitchenPacketPdf.new(packet([ recipe ]))
    pdf.send(:recipe_page, doc, recipe, "Double", false)
    assert_no_match(/Headcount/, texts.join("\n"))
    assert_includes texts, "Rice"
  end
end
