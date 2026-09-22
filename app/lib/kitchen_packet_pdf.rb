# Renders a KitchenPacket as the branded NY Kitchen recipe packet, matching the
# kitchen's hand-made Publisher handout: one recipe per page (auto-fit so it
# never spills), a serif title, two columns (ingredients | numbered directions),
# and a footer with the venue address (plus NY Kitchen's own footer marks when
# their files are present). Each recipe is printed twice: full quantities first,
# then single-station (half) amounts. Pure Prawn, no headless browser.
#
#   KitchenPacketPdf.new(packet).render  # => PDF bytes (String)
class KitchenPacketPdf
  FOOTER = "800 South Main Street, Canandaigua, NY 14424   |   www.nykitchen.com   |   (585) 394-7070".freeze
  # Points (72 = 1in): a 7.5 x 10in text area with 0.5in margins.
  PAGE   = [ 540, 720 ].freeze
  MARGIN = 36

  # Carlito is the open-source, metrically Calibri-compatible body font Lora
  # asked for. As a real embedded TTF it also covers the vulgar fraction block
  # (½ ⅓ ⅛ ...) the extractor uses.
  FONT_DIR   = Rails.root.join("vendor/fonts/carlito").freeze
  BODY_FONT  = "Carlito".freeze
  TITLE_FONT = "Times-Roman".freeze # built-in serif, to match the handout title

  # Largest body size that still fits the recipe on one page wins (auto-fit).
  BODY_SIZES = [ 12, 11, 10, 9, 8 ].freeze
  # "Fill the page" may go bigger than the everyday cap, so a short recipe is
  # not a small block at the top of an empty page.
  FILL_SIZES = [ 14, 13, *BODY_SIZES ].freeze

  # Per-recipe page spacing (Caitlin, 2026-09-10: short recipes looked
  # "crammed to the top"). Each setting is [gap under the title, vertical cell
  # padding in the two columns]; "fill" computes both from the leftover page.
  SPACING = {
    "normal" => { gap: 22, pad: 1.5 },
    "roomy"  => { gap: 44, pad: 4.0 },
    "fill"   => { gap: 22, pad: 1.5 }
  }.freeze
  MAX_PAD  = 14.0 # cap on padding so "fill" never turns a 3-line recipe into a ladder
  FILL_TOP = 0.90 # fill stretches the columns to about this share of the page

  # Ingredient column geometry, matching the kitchen's Word original
  # (Caitlin, 2026-09-21).
  #
  # AMOUNT_TAB: the amount column is a 0.5in tab, so every ingredient name
  # starts half an inch in ("3 c<tab>Diced potatoes") instead of floating out
  # at a third of the column. Widened only when an amount would otherwise wrap.
  # ING_EXTRA_PAD: ingredients breathe a little more than directions do. The
  # ask was "more space between ingredients", not between the steps.
  AMOUNT_TAB    = 36.0
  AMOUNT_GUTTER = 6.0 # the cell's right padding; an amount has this much clear air after it
  ING_EXTRA_PAD = 2.0
  DIR_EXTRA_PAD = 0.5

  # Optional footer marks: NY Kitchen's own brand files. Rendered only when
  # present, so the PDF still builds (address only) without them.
  LEFT_LOGO   = Rails.root.join("app/assets/images/nyk/iloveny.png").freeze
  RIGHT_LOGO  = Rails.root.join("app/assets/images/nyk/tasteny.png").freeze
  # NY Kitchen's own header lockup (NK mark + wordmark). Drawn as a vector
  # fallback if the file is missing so the PDF always builds.
  HEADER_LOGO = Rails.root.join("app/assets/images/nyk/nyk_header.png").freeze
  FOOTER_BAND = 40 # points reserved at the page bottom for the footer

  # Label for the full-quantity pages (the station amount is half, so the full
  # batch is two stations' worth). "Double" / "Single", no "station": Lora and
  # Caitlin, 2026-09-09.
  DUAL_STATION_LABEL = "Double".freeze

  VULGAR = "½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞⅐⅑⅒".freeze

  def initialize(packet)
    @packet = packet
  end

  def render
    doc = new_document
    recipes = @packet.recipes
    return empty(doc) if recipes.empty?

    first = true
    passes.each do |label, scaled|
      recipes.each do |recipe|
        doc.start_new_page unless first
        first = false
        recipe_page(doc, recipe, label, scaled)
      end
    end
    doc.render
  end

  private

  # The full amounts, then the half amounts. A packet with the half-amount
  # pages switched off prints the full amounts only, and then the "Double"
  # label would be the only thing on the page saying so, which reads as a
  # mistake when there is nothing to contrast it with -- so it is dropped too.
  def passes
    return [ [ nil, false ] ] unless @packet.single_pages?

    [ [ DUAL_STATION_LABEL, false ], [ @packet.station_label, true ] ]
  end

  def new_document
    doc = Prawn::Document.new(page_size: PAGE, margin: MARGIN)
    doc.font_families.update(BODY_FONT => {
      normal:      FONT_DIR.join("Carlito-Regular.ttf").to_s,
      bold:        FONT_DIR.join("Carlito-Bold.ttf").to_s,
      italic:      FONT_DIR.join("Carlito-Italic.ttf").to_s,
      bold_italic: FONT_DIR.join("Carlito-BoldItalic.ttf").to_s
    })
    doc.font(BODY_FONT)
    doc
  end

  # Carlito renders vulgar fractions natively; put a space between a number and a
  # glued fraction ("2½" -> "2 ½") so it reads cleanly.
  def tidy(str)
    no_dashes(str.to_s.gsub(/(?<=\d)([#{VULGAR}])/, ' \1'))
  end

  def no_dashes(str) = KitchenText.no_dashes(str)

  # A section heading prints with exactly one colon, whether or not the saved
  # name already carries one ("Parmesan herb sauce:" used to render as "::").
  def section_heading(name)
    "#{tidy(name).sub(/:+\z/, '')}:"
  end

  # A parenthetical like "(~300 g)" must never split across lines ("...(~300"
  # / "g)"). Prawn wraps at every space and Carlito has no glyph for a
  # non-breaking space, so once the body size is known, any item that will not
  # fit its column on one line is broken explicitly before the parenthetical.
  def keep_parentheticals(doc, rows, item_w, size)
    rows.each do |row|
      next unless row.is_a?(Array) && row.size == 2 && row[1].is_a?(String)
      item = row[1]
      next unless item.match?(/ \([^()]*\)\z/)
      next if doc.width_of(item, size: size) <= item_w
      row[1] = item.sub(/ (\([^()]*\))\z/, "\n\\1")
    end
    rows
  end

  def empty(doc)
    doc.text "No recipes on this packet yet.", align: :center, size: 13, color: "777777"
    doc.render
  end

  def recipe_page(doc, recipe, scale_label, scaled)
    if scale_label.present?
      doc.float do
        doc.bounding_box([ doc.bounds.right - 130, doc.bounds.top ], width: 130) do
          doc.text tidy(scale_label), size: 9, color: "444444", align: :right
        end
      end
    end

    brand(doc)
    doc.move_down 22
    # Headcount and station counts drive scaling and the pull sheet but are
    # not printed on the handout: nothing under the title (headcount removed
    # 2026-09-09 at Lora's request, station counts 2026-09-22 at Caitlin's).
    doc.font(TITLE_FONT, style: :bold) { doc.text tidy(recipe["title"]), size: @packet.title_size_pt, align: :center }
    spacing = KitchenPacket.spacing_for(recipe)
    doc.move_down SPACING.fetch(spacing)[:gap]

    top     = doc.cursor
    col_gap = 24
    ing_w   = (doc.bounds.width - col_gap) * @packet.ingredient_width_ratio
    dir_x   = ing_w + col_gap
    dir_w   = doc.bounds.width - dir_x

    ing_rows = ingredient_rows(recipe, scaled)
    dir_rows = direction_rows(recipe)

    # Auto-fit: pick the largest body size whose taller column still clears the
    # footer, so the whole recipe lands on this one page. "fill" then spends
    # the leftover page on a bigger gap under the title and airier rows.
    avail_h = top - FOOTER_BAND
    size, ing_rows, pad, extra_gap = fit_columns(doc, ing_rows, dir_rows, ing_w, dir_w, avail_h, spacing)
    top -= extra_gap

    # Directions on the right, ingredients on the left. Each in its own box so a
    # long column can't push the other down.
    doc.bounding_box([ dir_x, top ], width: dir_w) { render_directions(doc, dir_rows, dir_w, size, pad: pad) }
    doc.bounding_box([ 0, top ], width: ing_w) { render_ingredients(doc, ing_rows, ing_w, size, pad: pad) }

    footer(doc)
  end

  def brand(doc)
    if File.exist?(HEADER_LOGO)
      h = 26
      doc.image HEADER_LOGO.to_s, at: [ doc.bounds.left, doc.bounds.top ], height: h
      doc.move_down h # doc.image with at: does not advance the cursor
      return
    end

    # Vector fallback (NK circle + wordmark) if the logo file is missing.
    doc.float do
      r = 9
      doc.fill_color "111111"
      doc.line_width 2
      doc.stroke_color "111111"
      doc.stroke_circle [ doc.bounds.left + r, doc.bounds.top - r ], r + 2
      doc.draw_text "NK", at: [ doc.bounds.left + r - 7, doc.bounds.top - r - 3.5 ], size: 9, style: :bold
    end
    doc.indent(30) { doc.text "NEW YORK KITCHEN", size: 11, style: :bold, character_spacing: 1.5 }
    doc.fill_color "000000"
  end

  # ---- rows ----

  def ingredient_rows(recipe, scaled)
    rows = []
    last_section = :none
    Array(recipe["ingredients"]).each do |ing|
      section = ing["section"]
      if section.present? && section != last_section
        rows << [ { content: section_heading(section), colspan: 2, font_style: :bold } ]
      end
      last_section = section
      qty  = KitchenUnits.standardize(scaled ? ing["station_qty"] : ing["qty"])
      item = IngredientText.normalize(ing["item"])
      # A metric baked into the ingredient name ("Water (150 ml)") was written
      # for the full amounts, so it is wrong on the half-amount pages: the
      # amount halves and the parenthetical does not. Drop it there rather than
      # print a number that would have a single station double the water.
      item = drop_measure(item) if scaled
      # ... and only compute grams for flour when the name does not already
      # carry a weight, so a recipe never shows two different numbers for the
      # same thing ("Ap flour (250 g) (~240 g)").
      if item.match?(/\bflour/i) && !measure?(item) && (g = KitchenUnits.flour_grams(qty))
        item = "#{item} (~#{g} g)"
      end
      # An ingredient with no amount ("Salt, to taste") starts at the left
      # margin like the kitchen's Word original, instead of sitting indented in
      # the name column under the amounts. (Caitlin, 2026-09-21.)
      rows << if tidy(qty).blank?
        [ { content: tidy(item), colspan: 2 } ]
      else
        [ tidy(qty), tidy(item) ]
      end
    end
    rows
  end

  # A parenthetical that is nothing but a measurement: "(250 g)", "(150 ml)",
  # "(1.4 oz)", "(~240 g)". Deliberately narrow, so "(Note 2)", "(optional)"
  # and "(finely grated)" are never touched.
  MEASURE = /\s*\(\s*~?\s*[\d.,]+\s*(?:g|kg|ml|l|oz|lb)\s*\)/i

  def measure?(item) = item.match?(MEASURE)

  def drop_measure(item) = item.gsub(MEASURE, "").strip

  # [number, step] rows, numbered continuously; a section sub-heading is a
  # spanning bold row that does not consume a number.
  def direction_rows(recipe)
    rows = []
    n = 0
    Array(recipe["directions"]).each do |group|
      if group["section"].present?
        rows << [ { content: section_heading(group["section"]), colspan: 2, font_style: :bold } ]
      end
      Array(group["steps"]).each do |step|
        next if step.to_s.strip.empty?
        n += 1
        rows << [ "#{n}.", tidy(step) ]
      end
    end
    rows
  end

  # ---- fit + render ----

  # [amount column, name column]. The amount column is a 0.5in tab, grown only
  # as far as the widest amount needs ("1 ½ cups" at a big body size) so the
  # tab never costs an amount a wrapped line, and never eats the name column.
  def ing_widths(doc, rows, ing_w, size)
    w = [ AMOUNT_TAB, widest_amount(doc, rows, size) + AMOUNT_GUTTER ].max.clamp(AMOUNT_TAB, ing_w * 0.5)
    [ w, ing_w - w ]
  end

  def widest_amount(doc, rows, size)
    Array(rows).filter_map { |r|
      next unless r.is_a?(Array) && r.size == 2
      doc.width_of(r[0].to_s, size: size)
    }.max.to_f
  end

  # Ingredients carry a touch more vertical air than the steps beside them.
  def ing_pad(pad) = pad + ING_EXTRA_PAD
  def dir_pad(pad) = pad + DIR_EXTRA_PAD

  def dir_widths(dir_w, size)
    num_w = size * 1.9
    [ num_w, dir_w - num_w ]
  end

  # Returns [size, ingredient rows, pad, extra gap] for a spacing setting.
  # "normal" and "roomy" fit at their fixed padding; "fill" fits at the base
  # padding (allowing the larger FILL_SIZES), then spreads the leftover page:
  # a quarter of it as extra gap under the title, the rest as row padding on
  # the taller column, capped so the layout never looks stretched, and always
  # re-measured so it still clears the footer.
  def fit_columns(doc, ing_rows, dir_rows, ing_w, dir_w, avail_h, spacing)
    pad = SPACING.fetch(spacing)[:pad]
    return [ *fit_size(doc, ing_rows, dir_rows, ing_w, dir_w, avail_h, pad: pad), pad, 0 ] unless spacing == "fill"

    size, broken = fit_size(doc, ing_rows, dir_rows, ing_w, dir_w, avail_h, sizes: FILL_SIZES, pad: pad)
    ih = table_height(doc, broken, ing_widths(doc, broken, ing_w, size), size, pad: ing_pad(pad))
    dh = table_height(doc, dir_rows, dir_widths(dir_w, size), size, pad: dir_pad(pad))
    tall_h = [ ih, dh ].max
    tall_n = (ih >= dh ? broken : dir_rows).size
    leftover = avail_h - tall_h
    return [ size, broken, pad, 0 ] if leftover <= 0 || tall_n.zero?

    extra_gap = (leftover * 0.25).floor
    target_h  = avail_h * FILL_TOP - extra_gap
    # Each row carries the padding twice (top + bottom), so this is the padding
    # that lands the taller column on the target height.
    fill_pad = (pad + (target_h - tall_h) / (2.0 * tall_n)).clamp(pad, MAX_PAD)
    ih = table_height(doc, broken, ing_widths(doc, broken, ing_w, size), size, pad: ing_pad(fill_pad))
    dh = table_height(doc, dir_rows, dir_widths(dir_w, size), size, pad: dir_pad(fill_pad))
    return [ size, broken, pad, 0 ] if [ ih, dh ].max > avail_h - extra_gap
    [ size, broken, fill_pad, extra_gap ]
  end

  # Returns [size, ingredient rows] where the rows carry the parenthetical
  # breaks for that size: each candidate size is measured with its own breaks
  # applied, so a forced break can never add a line the fit did not budget.
  def fit_size(doc, ing_rows, dir_rows, ing_w, dir_w, avail_h, sizes: BODY_SIZES, pad: SPACING["normal"][:pad])
    broken = nil
    sizes.each do |size|
      # The name column is measured at this size, because the amount column
      # (and so the room left for names) depends on the size too.
      item_w = ing_widths(doc, ing_rows, ing_w, size)[1] - AMOUNT_GUTTER
      broken = keep_parentheticals(doc, ing_rows.map(&:dup), item_w, size)
      ih = table_height(doc, broken, ing_widths(doc, broken, ing_w, size), size, pad: ing_pad(pad))
      dh = table_height(doc, dir_rows, dir_widths(dir_w, size), size, pad: dir_pad(pad))
      return [ size, broken ] if [ ih, dh ].max <= avail_h
    end
    [ sizes.last, broken || ing_rows ]
  end

  def table_height(doc, rows, widths, size, pad: SPACING["normal"][:pad])
    return 0 if rows.blank?
    doc.make_table(rows, column_widths: widths,
                         cell_style: { borders: [], padding: [ pad, 6, pad, 0 ], size: size }).height
  rescue StandardError
    1_000_000
  end

  def render_ingredients(doc, rows, ing_w, size, pad: SPACING["normal"][:pad])
    underlined(doc, "Ingredients", size)
    doc.move_down 4
    return if rows.blank?
    doc.table(rows, column_widths: ing_widths(doc, rows, ing_w, size),
                    cell_style: { borders: [], padding: [ ing_pad(pad), AMOUNT_GUTTER, ing_pad(pad), 0 ], size: size })
  end

  def render_directions(doc, rows, dir_w, size, pad: SPACING["normal"][:pad])
    underlined(doc, "Directions", size)
    doc.move_down 4
    return if rows.blank?
    doc.table(rows, column_widths: dir_widths(dir_w, size),
                    cell_style: { borders: [], padding: [ dir_pad(pad), AMOUNT_GUTTER, dir_pad(pad), 0 ], size: size, valign: :top })
  end

  def underlined(doc, label, size)
    doc.formatted_text [ { text: "#{label}:", styles: [ :bold, :underline ], size: [ size + 2, 13 ].min } ]
  end

  # ---- footer ----

  def footer(doc)
    logo_h   = 18
    center_y = 12 # shared vertical center: the logos sit on the same line as the address

    if File.exist?(LEFT_LOGO)
      doc.image LEFT_LOGO.to_s, at: [ doc.bounds.left, center_y + logo_h / 2.0 ], height: logo_h
    end
    if File.exist?(RIGHT_LOGO)
      w = scaled_image_width(RIGHT_LOGO, logo_h)
      doc.image RIGHT_LOGO.to_s, at: [ doc.bounds.right - w, center_y + logo_h / 2.0 ], height: logo_h
    end

    box_h = 16
    doc.text_box FOOTER, at: [ doc.bounds.left, center_y + box_h / 2.0 ], width: doc.bounds.width,
                         height: box_h, align: :center, valign: :center, size: 7, color: "555555"
  end

  # Width a PNG occupies when scaled to a target height (to right-align the
  # right-hand mark). Reads width/height straight from the PNG IHDR.
  def scaled_image_width(path, height)
    bytes = File.binread(path, 24)
    w = bytes[16, 4].unpack1("N")
    h = bytes[20, 4].unpack1("N")
    return height if w.to_i.zero? || h.to_i.zero?
    height * (w.to_f / h)
  rescue StandardError
    height * 3
  end
end
