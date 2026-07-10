# Renders the NY Kitchen grocery list / single-class pull sheet as a real PDF
# download. It uses the same data that backs the HTML sheet, but keeps the
# layout intentionally simple so it stays reliable on Fly without a browser.
class KitchenGroceryPdf
  PAGE = "LETTER".freeze
  MARGIN = 36
  FONT_DIR = Rails.root.join("vendor/fonts/carlito").freeze
  BODY_FONT = "Carlito".freeze

  def initialize(result:, with_recipe:, range:, total_headcount:, single: false, single_event: nil, show_prices: false)
    @result = result
    @with_recipe = Array(with_recipe)
    @range = range
    @total_headcount = total_headcount.to_i
    @single = single
    @single_event = single_event
    @show_prices = show_prices && !single
  end

  def render
    doc = new_document
    header(doc)

    unless @result&.ok?
      doc.move_down 24
      doc.text "No grocery list is available for this range.", size: 12, color: "666666"
      return doc.render
    end

    categories(doc)
    to_taste(doc)
    equipment(doc)
    total(doc)
    covers(doc)
    doc.render
  end

  private

  def new_document
    doc = Prawn::Document.new(page_size: PAGE, margin: MARGIN)
    doc.font_families.update(BODY_FONT => {
      normal: FONT_DIR.join("Carlito-Regular.ttf").to_s,
      bold: FONT_DIR.join("Carlito-Bold.ttf").to_s,
      italic: FONT_DIR.join("Carlito-Italic.ttf").to_s,
      bold_italic: FONT_DIR.join("Carlito-BoldItalic.ttf").to_s
    })
    doc.font(BODY_FONT)
    doc
  end

  def header(doc)
    doc.text sheet_title, size: 20, style: :bold
    doc.move_down 6
    doc.stroke_horizontal_rule
    doc.move_down 12

    if @single && @single_event
      doc.text @single_event.name.to_s, size: 14, style: :bold
      doc.text "#{@single_event.start_at.strftime('%b %-d')} | #{plural(@total_headcount, 'person')} booked", size: 11, color: "666666"
    else
      doc.text "#{@range.first.strftime('%b %-d')} to #{@range.last.strftime('%b %-d')} | #{plural(@with_recipe.size, 'class')} with recipes | #{plural(@total_headcount, 'person')} booked", size: 11, color: "666666"
    end
    doc.move_down 16
  end

  def categories(doc)
    Array(@result.categories).each do |cat|
      items = Array(cat["items"])
      next if items.empty?

      section(doc, cat["name"])
      rows = items.map do |it|
        qty = KitchenUnits.standardize(it["quantity"])
        item = it["item"].to_s
        item += "  #{format('$%.2f', it['price'].to_f)}" if @show_prices && it["price"].to_f.positive?
        [ checkbox, tidy(qty), tidy(item) ]
      end
      table(doc, rows, [ 18, 90, doc.bounds.width - 108 ])
    end
  end

  def to_taste(doc)
    return if @result.to_taste.blank?

    section(doc, "To taste / on hand")
    doc.text tidy(@result.to_taste.join(", ")), size: 12, color: "444444"
    doc.move_down 12
  end

  def equipment(doc)
    station_equipment(doc)
    purchase_equipment(doc)
  end

  # Owned gear, just set up: pull sheet ONLY (single-class run).
  def station_equipment(doc)
    return unless @single

    c = @with_recipe.first
    items = Array(c&.dig(:packet)&.equipment)
    return if items.empty?

    label = "Equipment per station"
    label += " (set up at each of #{plural(c[:stations], 'station')})" if c[:stations]
    section(doc, label)
    table(doc, items.map { |eq| [ checkbox, tidy(eq) ] }, [ 18, doc.bounds.width - 18 ])
    doc.move_down 4
  end

  # Gear to buy: pull sheet AND grocery list. Deduped union across the classes.
  def purchase_equipment(doc)
    items = @with_recipe.flat_map { |c| Array(c[:packet]&.purchase_equipment) }
                        .map { |e| e.to_s.strip }.reject(&:blank?).uniq { |e| e.downcase }
    return if items.empty?

    section(doc, "Equipment to purchase")
    table(doc, items.map { |eq| [ checkbox, tidy(eq) ] }, [ 18, doc.bounds.width - 18 ])
    doc.move_down 4
  end

  def total(doc)
    return unless @show_prices

    est_total = @result.categories.sum { |cat| Array(cat["items"]).sum { |i| i["price"].to_f } }
    return unless est_total.positive?

    doc.move_down 10
    doc.stroke_horizontal_rule
    doc.move_down 8
    doc.text "Estimated total: #{format('$%.2f', est_total)}", size: 14, style: :bold
    doc.text "Rough estimate of typical US grocery prices, for budgeting only.", size: 9, color: "777777"
  end

  def covers(doc)
    return if @with_recipe.empty?

    doc.move_down 18
    doc.stroke_horizontal_rule
    doc.move_down 8
    doc.text(
      "Covers: #{@with_recipe.map { |c| "#{c[:event].name} (#{c[:headcount]} booked, #{c[:stations]} stations)" }.join(' | ')}",
      size: 9,
      color: "777777"
    )
  end

  def section(doc, label)
    doc.move_down 8
    doc.text tidy(label).upcase, size: 12, style: :bold, color: "444444"
    doc.move_down 4
  end

  def table(doc, rows, widths)
    return if rows.empty?

    doc.table(rows, cell_style: { borders: [ :bottom ], border_color: "EEEEEE", padding: [ 3, 4, 3, 0 ], size: 12 },
                    column_widths: widths)
    doc.move_down 6
  end

  def checkbox
    "[ ]"
  end

  def sheet_title
    @single ? "NY Kitchen Pull Sheet" : "NY Kitchen Grocery List"
  end

  def plural(count, noun)
    "#{count} #{noun.pluralize(count)}"
  end

  def tidy(value)
    value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
  end
end
