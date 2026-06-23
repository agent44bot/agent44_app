# Renders a KitchenHandout as the branded NY Kitchen recipe packet, the same
# layout as the kitchen's hand-made Publisher PDFs: one page per recipe at full
# quantities, then the same recipes again at single-station quantities (tagged
# top-right). Pure Prawn, no headless browser, so it runs inside the Fly app
# with no extra system dependencies.
#
#   KitchenHandoutPdf.new(handout).render  # => PDF bytes (String)
class KitchenHandoutPdf
  FOOTER = "800 South Main Street, Canandaigua, NY 14424   |   www.nykitchen.com   |   (585) 394-7070".freeze
  # Points (72 = 1in): a 7.5 x 10in text area, the same printable box as the
  # HTML packet, with 0.5in margins.
  PAGE   = [ 540, 720 ].freeze
  MARGIN = 36

  # Carlito is the open-source, metrically Calibri-compatible body font Lora
  # asked for ("size 13 / Calibri"). As a real embedded TTF it also covers the
  # vulgar fraction block (½ ⅓ ⅛ ...) the extractor uses, so those render
  # natively instead of being spelled out as "1/2".
  FONT_DIR  = Rails.root.join("vendor/fonts/carlito").freeze
  BODY_FONT = "Carlito".freeze
  BODY_SIZE = 13

  # Label for the full-quantity pages. The station amount (station_qty) is half
  # the full amount, so the full batch is two stations' worth.
  DUAL_STATION_LABEL = "Dual station".freeze

  # Vulgar fractions, for spacing them off a leading number ("2½" -> "2 ½").
  VULGAR = "½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞⅐⅑⅒".freeze

  def initialize(handout)
    @handout = handout
  end

  def render
    doc = new_document
    recipes = @handout.recipes
    return empty(doc) if recipes.empty?

    first = true
    # Two passes, every page labeled: the full-quantity batch (labeled "Dual
    # station", since the station amount is exactly half) first, then the
    # single-station set. [label, scaled?] — scaled? picks the qty column.
    [ [ DUAL_STATION_LABEL, false ], [ @handout.station_label, true ] ].each do |label, scaled|
      recipes.each do |recipe|
        doc.start_new_page unless first
        first = false
        recipe_page(doc, recipe, label, scaled)
      end
    end
    doc.render
  end

  private

  # A Prawn doc with Carlito registered and set as the default font.
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

  # Carlito renders vulgar fractions natively; just put a space between a number
  # and a glued fraction ("2½" -> "2 ½") so it reads cleanly. UTF-8 throughout;
  # a TTF substitutes a blank for any glyph it lacks rather than raising.
  def tidy(str)
    str.to_s.gsub(/(?<=\d)([#{VULGAR}])/, ' \1')
  end

  def empty(doc)
    doc.text "No recipes on this handout yet.", align: :center, size: 13, color: "777777"
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
    doc.move_down 24
    doc.text tidy(recipe["title"]), size: 26, style: :bold, align: :center
    if (hc = recipe["headcount"].to_i) > 0
      doc.move_down 6
      doc.text "Headcount: #{hc}", size: 12, color: "555555", align: :center
    end
    doc.move_down 28

    # Two columns: ingredients (narrow) | directions (wide), each in its own
    # bounding box so neither pushes the other down.
    top = doc.cursor
    col_gap = 24
    ing_w = (doc.bounds.width - col_gap) * 0.42
    dir_x = ing_w + col_gap
    start_page = doc.page_number

    # Draw directions FIRST so they always land on this page beside the
    # ingredients. Rendering ingredients first paginated the doc forward when
    # the list was long, dropping directions onto a later page and leaving this
    # page's right column blank. We then jump back and lay the ingredients down
    # the left, so a long list spills onto its own continuation page instead.
    doc.bounding_box([ dir_x, top ], width: doc.bounds.width - dir_x) { directions(doc, recipe) }
    dir_end_page = doc.page_number

    doc.go_to_page(start_page)
    doc.bounding_box([ 0, top ], width: ing_w) { ingredients(doc, recipe, scaled) }
    ing_end_page = doc.page_number

    # Continue after whichever column ran longest so the footer (and the next
    # recipe's page) never overwrites a column that spilled past page one.
    doc.go_to_page([ dir_end_page, ing_end_page ].max)
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

  def ingredients(doc, recipe, scaled)
    underlined(doc, "Ingredients")
    doc.move_down 4
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
      # Flour by volume is imprecise, so show its weight too (Lora's request).
      if item.match?(/\bflour/i) && (g = KitchenUnits.flour_grams(qty))
        item = "#{item} (~#{g} g)"
      end
      rows << [ tidy(qty), tidy(item) ]
    end
    return if rows.empty?

    doc.font(BODY_FONT, size: BODY_SIZE) do
      doc.table(rows, cell_style: { borders: [], padding: [ 1.5, 6, 1.5, 0 ] },
                      column_widths: [ doc.bounds.width * 0.40, doc.bounds.width * 0.60 ])
    end
  end

  def directions(doc, recipe)
    underlined(doc, "Directions")
    doc.move_down 4
    doc.font(BODY_FONT, size: BODY_SIZE) do
      Array(recipe["directions"]).each do |group|
        if group["section"].present?
          doc.move_down 4
          doc.text "#{tidy(group['section'])}:", style: :bold
          doc.move_down 2
        end
        Array(group["steps"]).each do |step|
          if step.to_s.strip.empty?
            doc.move_down 7 # a blank line between steps prints as a paragraph gap
          else
            doc.text tidy(step), indent_paragraphs: 0, leading: 1
            doc.move_down 4
          end
        end
      end
    end
  end

  def underlined(doc, label)
    doc.formatted_text [ { text: "#{label}:", styles: [ :bold, :underline ], size: 13 } ]
  end

  def footer(doc)
    doc.bounding_box([ 0, doc.bounds.bottom + 10 ], width: doc.bounds.width, height: 10) do
      doc.text FOOTER, size: 8, color: "555555", align: :center
    end
  end
end
