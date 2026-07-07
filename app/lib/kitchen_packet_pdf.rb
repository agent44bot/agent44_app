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

  # Optional footer marks: NY Kitchen's own brand files. Rendered only when
  # present, so the PDF still builds (address only) without them.
  LEFT_LOGO   = Rails.root.join("app/assets/images/nyk/iloveny.png").freeze
  RIGHT_LOGO  = Rails.root.join("app/assets/images/nyk/tasteny.png").freeze
  FOOTER_BAND = 40 # points reserved at the page bottom for the footer

  # Label for the full-quantity pages (the station amount is half, so the full
  # batch is two stations' worth).
  DUAL_STATION_LABEL = "Dual station".freeze

  VULGAR = "½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞⅐⅑⅒".freeze

  def initialize(packet)
    @packet = packet
  end

  def render
    doc = new_document
    recipes = @packet.recipes
    return empty(doc) if recipes.empty?

    first = true
    [ [ DUAL_STATION_LABEL, false ], [ @packet.station_label, true ] ].each do |label, scaled|
      recipes.each do |recipe|
        doc.start_new_page unless first
        first = false
        recipe_page(doc, recipe, label, scaled)
      end
    end
    doc.render
  end

  private

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
    str.to_s.gsub(/(?<=\d)([#{VULGAR}])/, ' \1')
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
    doc.font(TITLE_FONT, style: :bold) { doc.text tidy(recipe["title"]), size: 24, align: :center }
    if (hc = recipe["headcount"].to_i) > 0
      doc.move_down 6
      doc.text "Headcount: #{hc}", size: 12, color: "555555", align: :center
    end
    doc.move_down 22

    top     = doc.cursor
    col_gap = 24
    ing_w   = (doc.bounds.width - col_gap) * 0.42
    dir_x   = ing_w + col_gap
    dir_w   = doc.bounds.width - dir_x

    ing_rows = ingredient_rows(recipe, scaled)
    dir_rows = direction_rows(recipe)

    # Auto-fit: pick the largest body size whose taller column still clears the
    # footer, so the whole recipe lands on this one page.
    avail_h = top - FOOTER_BAND
    size = fit_size(doc, ing_rows, dir_rows, ing_w, dir_w, avail_h)

    # Directions on the right, ingredients on the left. Each in its own box so a
    # long column can't push the other down.
    doc.bounding_box([ dir_x, top ], width: dir_w) { render_directions(doc, dir_rows, dir_w, size) }
    doc.bounding_box([ 0, top ], width: ing_w) { render_ingredients(doc, ing_rows, ing_w, size) }

    footer(doc)
  end

  def brand(doc)
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
        rows << [ { content: "#{tidy(section)}:", colspan: 2, font_style: :bold } ]
      end
      last_section = section
      qty  = KitchenUnits.standardize(scaled ? ing["station_qty"] : ing["qty"])
      item = IngredientText.normalize(ing["item"])
      if item.match?(/\bflour/i) && (g = KitchenUnits.flour_grams(qty))
        item = "#{item} (~#{g} g)"
      end
      rows << [ tidy(qty), tidy(item) ]
    end
    rows
  end

  # [number, step] rows, numbered continuously; a section sub-heading is a
  # spanning bold row that does not consume a number.
  def direction_rows(recipe)
    rows = []
    n = 0
    Array(recipe["directions"]).each do |group|
      if group["section"].present?
        rows << [ { content: "#{tidy(group['section'])}:", colspan: 2, font_style: :bold } ]
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

  def ing_widths(ing_w)
    [ ing_w * 0.34, ing_w * 0.66 ]
  end

  def dir_widths(dir_w, size)
    num_w = size * 1.9
    [ num_w, dir_w - num_w ]
  end

  def fit_size(doc, ing_rows, dir_rows, ing_w, dir_w, avail_h)
    BODY_SIZES.each do |size|
      ih = table_height(doc, ing_rows, ing_widths(ing_w), size)
      dh = table_height(doc, dir_rows, dir_widths(dir_w, size), size)
      return size if [ ih, dh ].max <= avail_h
    end
    BODY_SIZES.last
  end

  def table_height(doc, rows, widths, size)
    return 0 if rows.blank?
    doc.make_table(rows, column_widths: widths,
                         cell_style: { borders: [], padding: [ 1.5, 6, 1.5, 0 ], size: size }).height
  rescue StandardError
    1_000_000
  end

  def render_ingredients(doc, rows, ing_w, size)
    underlined(doc, "Ingredients", size)
    doc.move_down 4
    return if rows.blank?
    doc.table(rows, column_widths: ing_widths(ing_w),
                    cell_style: { borders: [], padding: [ 1.5, 6, 1.5, 0 ], size: size })
  end

  def render_directions(doc, rows, dir_w, size)
    underlined(doc, "Directions", size)
    doc.move_down 4
    return if rows.blank?
    doc.table(rows, column_widths: dir_widths(dir_w, size),
                    cell_style: { borders: [], padding: [ 2, 6, 2, 0 ], size: size, valign: :top })
  end

  def underlined(doc, label, size)
    doc.formatted_text [ { text: "#{label}:", styles: [ :bold, :underline ], size: [ size + 2, 13 ].min } ]
  end

  # ---- footer ----

  def footer(doc)
    logo_h = 22
    y = FOOTER_BAND - 6 # top edge of the logos, measured from the content bottom

    if File.exist?(LEFT_LOGO)
      doc.image LEFT_LOGO.to_s, at: [ doc.bounds.left, y ], height: logo_h
    end
    if File.exist?(RIGHT_LOGO)
      w = scaled_image_width(RIGHT_LOGO, logo_h)
      doc.image RIGHT_LOGO.to_s, at: [ doc.bounds.right - w, y ], height: logo_h
    end

    doc.text_box FOOTER, at: [ doc.bounds.left, y - logo_h + 4 ], width: doc.bounds.width,
                         height: logo_h, align: :center, valign: :center, size: 7, color: "555555"
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
