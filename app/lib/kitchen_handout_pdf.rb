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

  # Prawn's built-in fonts only cover WinAnsi, which is missing the vulgar
  # fraction block (⅓ ⅔ ⅛ ...) the extractor uses for station amounts. Render
  # fractions as ASCII ("2½ c" -> "2 1/2 c") so they're legible and can't crash
  # the page, rather than bundling a TTF just for a handful of glyphs.
  VULGAR = {
    "½" => "1/2", "⅓" => "1/3", "⅔" => "2/3", "¼" => "1/4", "¾" => "3/4",
    "⅕" => "1/5", "⅖" => "2/5", "⅗" => "3/5", "⅘" => "4/5", "⅙" => "1/6",
    "⅚" => "5/6", "⅛" => "1/8", "⅜" => "3/8", "⅝" => "5/8", "⅞" => "7/8",
    "⅐" => "1/7", "⅑" => "1/9", "⅒" => "1/10"
  }.freeze

  def initialize(handout)
    @handout = handout
  end

  def render
    doc = Prawn::Document.new(page_size: PAGE, margin: MARGIN)
    recipes = @handout.recipes
    return empty(doc) if recipes.empty?

    first = true
    # Full-quantity pages first, then the single-station set.
    [ nil, @handout.station_label ].each do |scale_tag|
      recipes.each do |recipe|
        doc.start_new_page unless first
        first = false
        recipe_page(doc, recipe, scale_tag)
      end
    end
    doc.render
  end

  private

  # Make a string safe for Prawn's AFM fonts: ASCII-ify fractions, insert a
  # space between a number and a fraction (2½ -> 2 1/2), then drop anything
  # still outside WinAnsi so an odd glyph can never raise mid-render.
  def tidy(str)
    s = str.to_s
    VULGAR.each { |uni, ascii| s = s.gsub(/(?<=\d)#{uni}/, " #{ascii}").gsub(uni, ascii) }
    s.encode(Encoding::Windows_1252, invalid: :replace, undef: :replace, replace: "")
     .encode(Encoding::UTF_8)
  end

  def empty(doc)
    doc.text "No recipes on this handout yet.", align: :center, size: 13, color: "777777"
    doc.render
  end

  def recipe_page(doc, recipe, scale_tag)
    if scale_tag.present?
      doc.float do
        doc.bounding_box([ doc.bounds.right - 130, doc.bounds.top ], width: 130) do
          doc.text tidy(scale_tag), size: 9, color: "444444", align: :right
        end
      end
    end

    brand(doc)
    doc.move_down 24
    doc.font("Times-Roman") { doc.text tidy(recipe["title"]), size: 26, style: :bold, align: :center }
    doc.move_down 28

    # Two columns: ingredients (narrow) | directions (wide). column_box keeps
    # them independent so a long directions list doesn't push ingredients.
    top = doc.cursor
    col_gap = 24
    ing_w = (doc.bounds.width - col_gap) * 0.42
    dir_x = ing_w + col_gap

    doc.bounding_box([ 0, top ], width: ing_w) { ingredients(doc, recipe, scale_tag) }
    doc.bounding_box([ dir_x, top ], width: doc.bounds.width - dir_x) { directions(doc, recipe) }

    footer(doc)
  end

  def brand(doc)
    doc.float do
      r = 9
      doc.fill_color "111111"
      doc.line_width 2
      doc.stroke_color "111111"
      doc.stroke_circle [ doc.bounds.left + r, doc.bounds.top - r ], r + 2
      doc.font("Helvetica") do
        doc.draw_text "NK", at: [ doc.bounds.left + r - 7, doc.bounds.top - r - 3.5 ], size: 9, style: :bold
      end
    end
    doc.font("Helvetica") do
      doc.indent(30) { doc.text "NEW YORK KITCHEN", size: 11, style: :bold, character_spacing: 1.5 }
    end
    doc.fill_color "000000"
  end

  def ingredients(doc, recipe, scale_tag)
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
      qty = scale_tag ? ing["station_qty"] : ing["qty"]
      rows << [ tidy(KitchenUnits.standardize(qty)), tidy(IngredientText.clean(ing["item"])) ]
    end
    return if rows.empty?

    doc.font("Helvetica", size: 10) do
      doc.table(rows, cell_style: { borders: [], padding: [ 1.5, 6, 1.5, 0 ] },
                      column_widths: [ doc.bounds.width * 0.40, doc.bounds.width * 0.60 ])
    end
  end

  def directions(doc, recipe)
    underlined(doc, "Directions")
    doc.move_down 4
    doc.font("Helvetica", size: 10) do
      Array(recipe["directions"]).each do |group|
        if group["section"].present?
          doc.move_down 4
          doc.text "#{tidy(group['section'])}:", style: :bold
          doc.move_down 2
        end
        Array(group["steps"]).each do |step|
          doc.text tidy(step), indent_paragraphs: 0, leading: 1
          doc.move_down 4
        end
      end
    end
  end

  def underlined(doc, label)
    doc.font("Helvetica") do
      doc.formatted_text [ { text: "#{label}:", styles: [ :bold, :underline ], size: 12 } ]
    end
  end

  def footer(doc)
    doc.font("Helvetica") do
      doc.bounding_box([ 0, doc.bounds.bottom + 10 ], width: doc.bounds.width, height: 10) do
        doc.text FOOTER, size: 8, color: "555555", align: :center
      end
    end
  end
end
