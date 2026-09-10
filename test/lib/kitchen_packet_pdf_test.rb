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

  test "a long ingredient with a parenthetical still fits the page at the chosen size" do
    long = "Stone-ground organic heirloom cornmeal from the Finger Lakes mill (~300 g)"
    recipe = { "title" => "Bread",
               "ingredients" => (1..8).map { |i| { "qty" => "#{i} c", "station_qty" => "1 c", "item" => long, "section" => nil } },
               "directions" => [ { "section" => nil, "steps" => [ "Mix." ] } ] }
    pdf = KitchenPacketPdf.new(packet([ recipe ]))
    doc = pdf.send(:new_document)
    rows = pdf.send(:ingredient_rows, recipe, false)
    ing_w = (doc.bounds.width - 24) * 0.42
    avail_h = doc.bounds.top - 120 - KitchenPacketPdf::FOOTER_BAND
    size, broken = pdf.send(:fit_size, doc, rows, [], ing_w, doc.bounds.width - ing_w - 24, avail_h)
    height = pdf.send(:table_height, doc, broken, pdf.send(:ing_widths, ing_w), size)
    assert height <= avail_h, "rows measured with their breaks must fit the budget (#{height} > #{avail_h})"
    assert size > KitchenPacketPdf::BODY_SIZES.last, "fixture should fit above the smallest size (got #{size})"
    # The unbroken rows at that size are shorter or equal; the old code sized on
    # those and then broke, which could overflow. Now the broken rows are what fit.
    unbroken = pdf.send(:table_height, doc, rows, pdf.send(:ing_widths, ing_w), size)
    assert unbroken <= height
    assert broken.all? { |r| r[1].include?("\n(~300 g)") }, "every long item breaks before its parenthetical"
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

  # ---- page spacing (Caitlin, 2026-09-10) ----

  SHORT = { "title" => "Sauce",
            "ingredients" => [ { "qty" => "2 T", "station_qty" => "1 T", "item" => "Butter", "section" => nil },
                               { "qty" => "1", "station_qty" => "1/2", "item" => "Lemon", "section" => nil } ],
            "directions" => [ { "section" => nil, "steps" => [ "Melt.", "Squeeze.", "Stir." ] } ] }.freeze

  def fit(recipe, spacing)
    pdf = KitchenPacketPdf.new(packet([ recipe ]))
    doc = pdf.send(:new_document)
    ing_rows = pdf.send(:ingredient_rows, recipe, false)
    dir_rows = pdf.send(:direction_rows, recipe)
    ing_w = (doc.bounds.width - 24) * 0.42
    dir_w = doc.bounds.width - ing_w - 24
    avail_h = doc.bounds.top - 120 - KitchenPacketPdf::FOOTER_BAND
    size, rows, pad, gap = pdf.send(:fit_columns, doc, ing_rows, dir_rows, ing_w, dir_w, avail_h, spacing)
    tall = [ pdf.send(:table_height, doc, rows, pdf.send(:ing_widths, ing_w), size, pad: pad),
             pdf.send(:table_height, doc, dir_rows, pdf.send(:dir_widths, dir_w, size), size, pad: pad) ].max
    { size: size, pad: pad, gap: gap, tall: tall, avail: avail_h }
  end

  test "spacing reads normal for anything but the three settings" do
    assert_equal "normal", KitchenPacket.spacing_for({})
    assert_equal "normal", KitchenPacket.spacing_for("spacing" => "huge")
    assert_equal "fill", KitchenPacket.spacing_for("spacing" => "fill")
    assert_equal "roomy", KitchenPacket.spacing_for("spacing" => "roomy")
  end

  test "normal is the old layout: 12pt cap, base padding, no extra gap" do
    r = fit(SHORT, "normal")
    assert_equal [ 12, KitchenPacketPdf::SPACING["normal"][:pad], 0 ], [ r[:size], r[:pad], r[:gap] ]
  end

  test "roomy keeps the size but pads the rows and the gap under the title" do
    r = fit(SHORT, "roomy")
    assert_equal 12, r[:size]
    assert_equal KitchenPacketPdf::SPACING["roomy"][:pad], r[:pad]
    assert_operator KitchenPacketPdf::SPACING["roomy"][:gap], :>, KitchenPacketPdf::SPACING["normal"][:gap]
  end

  test "fill spreads a short recipe: bigger text, a gap under the title, airier rows, still clear of the footer" do
    r = fit(SHORT, "fill")
    assert_equal 14, r[:size], "a three-line recipe should get the largest fill size"
    assert_operator r[:gap], :>, 0
    assert_operator r[:pad], :>, KitchenPacketPdf::SPACING["normal"][:pad]
    assert_operator r[:pad], :<=, KitchenPacketPdf::MAX_PAD
    assert_operator r[:tall] + r[:gap], :<=, r[:avail]
    normal = fit(SHORT, "normal")
    assert_operator r[:tall], :>, normal[:tall] * 1.5, "fill should visibly stretch the columns"
  end

  test "fill on a long recipe falls back to a plain fit and never overflows the page" do
    long = { "title" => "Bread",
             "ingredients" => (1..14).map { |i| { "qty" => "#{i} c", "station_qty" => "1 c", "item" => "Flour #{i}", "section" => nil } },
             "directions" => [ { "section" => nil, "steps" => (1..18).map { |i| "Step #{i}: knead the dough for a while, rest it, fold it, rest it again, then shape it." } } ] }
    r = fit(long, "fill")
    assert_operator r[:tall] + r[:gap], :<=, r[:avail]
    assert_operator r[:size], :<, 14, "a page-filling recipe should not get the biggest size"
  end

  test "a fill recipe renders on one page with the columns pushed down" do
    doc = Prawn::Document.new
    moves = []
    doc.define_singleton_method(:text) { |*_| nil }
    doc.define_singleton_method(:table) { |*_| nil }
    doc.define_singleton_method(:make_table) { |*_| Struct.new(:height).new(10) }
    doc.define_singleton_method(:move_down) { |n| moves << n }
    boxes = []
    doc.define_singleton_method(:bounding_box) { |pos, **_| boxes << pos; nil }
    KitchenPacketPdf.new(packet([ SHORT.merge("spacing" => "fill") ])).send(:recipe_page, doc, SHORT.merge("spacing" => "fill"), "Double", false)
    # The first box is the "Double" label float; the last two are the columns,
    # which start at the same y, below where a normal page would put them.
    assert_equal 1, boxes.last(2).map { |pos| pos[1] }.uniq.size
    normal_doc = Prawn::Document.new
    normal_doc.define_singleton_method(:text) { |*_| nil }
    normal_doc.define_singleton_method(:table) { |*_| nil }
    normal_doc.define_singleton_method(:make_table) { |*_| Struct.new(:height).new(10) }
    nboxes = []
    normal_doc.define_singleton_method(:bounding_box) { |pos, **_| nboxes << pos; nil }
    KitchenPacketPdf.new(packet([ SHORT ])).send(:recipe_page, normal_doc, SHORT, "Double", false)
    assert_operator boxes.last[1], :<, nboxes.last[1]
  end
end
