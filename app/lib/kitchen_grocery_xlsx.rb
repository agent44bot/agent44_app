require "caxlsx"

# Renders the NY Kitchen grocery list / single-class pull sheet as a real .xlsx
# workbook (Lora asked to edit it in Excel). Same data that backs the HTML sheet
# and the PDF, but laid out as spreadsheet columns, and it leads with the class
# names + dates in the list (which the multi-class PDF only summarised).
class KitchenGroceryXlsx
  CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

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
    package = Axlsx::Package.new
    wb = package.workbook
    @s = build_styles(wb)

    wb.add_worksheet(name: sheet_name) do |sheet|
      @sheet = sheet
      header
      classes_section
      grocery_section
      to_taste_section
      equipment_section
      total_section
    end

    package.to_stream.read
  end

  private

  def build_styles(wb)
    # Axlsx wants 8-digit ARGB colours.
    {
      title:   wb.styles.add_style(sz: 16, b: true),
      caption: wb.styles.add_style(sz: 10, fg_color: "FF777777"),
      section: wb.styles.add_style(sz: 12, b: true, fg_color: "FF444444"),
      head:    wb.styles.add_style(b: true, bg_color: "FFF0F0F0", border: { style: :thin, color: "FFDDDDDD" }),
      price:   wb.styles.add_style(num_fmt: 7) # $#,##0.00
    }
  end

  def row(values = [], **opts)
    @sheet.add_row(values, **opts)
  end

  def header
    row [ sheet_title ], style: @s[:title]
    row [ summary_line ], style: @s[:caption]
    row []
  end

  def summary_line
    if @single && @single_event
      "#{@single_event.name} | #{@single_event.start_at.strftime('%a %b %-d')} | #{plural(@total_headcount, 'person')} booked"
    else
      "#{@range.first.strftime('%a %b %-d')} to #{@range.last.strftime('%a %b %-d')} | " \
        "#{plural(@with_recipe.size, 'class')} with recipes | #{plural(@total_headcount, 'person')} booked"
    end
  end

  # The class names + dates Lora wanted in the download (the web sheet shows
  # them; the multi-class PDF didn't). Skipped on a single-class pull sheet,
  # where the header line already names the one class.
  def classes_section
    return if @single || @with_recipe.empty?

    row [ "Classes in this list" ], style: @s[:section]
    row [ "Class", "Date", "People booked" ], style: @s[:head]
    @with_recipe.each do |c|
      row [ c[:event].name.to_s, c[:event].start_at.strftime("%a %b %-d"), c[:headcount].to_i ]
    end
    row []
  end

  def grocery_section
    return unless @result&.ok?

    row [ "Grocery list" ], style: @s[:section]
    headers = [ "Category", "Item", "Quantity" ]
    headers << "Est. price" if @show_prices
    row headers, style: @s[:head]

    Array(@result.categories).each do |cat|
      Array(cat["items"]).each do |it|
        cells = [ cat["name"].to_s, it["item"].to_s, KitchenUnits.standardize(it["quantity"]).to_s ]
        if @show_prices
          cells << it["price"].to_f
          row cells, style: [ nil, nil, nil, @s[:price] ]
        else
          row cells
        end
      end
    end
    row []
  end

  def to_taste_section
    return if @result&.to_taste.blank?

    row [ "To taste / on hand" ], style: @s[:section]
    row [ @result.to_taste.join(", ") ]
    row []
  end

  def equipment_section
    equip_classes = @with_recipe.select { |c| Array(c[:packet]&.equipment).any? }
    return if equip_classes.empty?

    row [ "Equipment per station" ], style: @s[:section]
    row [ "Class", "Equipment" ], style: @s[:head]
    equip_classes.each do |c|
      label = @single ? "" : c[:event].name.to_s
      Array(c[:packet].equipment).each do |eq|
        row [ label, eq.to_s ]
        label = "" # only label the first row of each class
      end
    end
    row []
  end

  def total_section
    return unless @show_prices

    est_total = Array(@result&.categories).sum { |cat| Array(cat["items"]).sum { |i| i["price"].to_f } }
    return unless est_total.positive?

    row [ "Estimated total", est_total ], style: [ @s[:section], @s[:price] ]
    row [ "Rough estimate of typical US grocery prices, for budgeting only." ], style: @s[:caption]
  end

  def sheet_name
    @single ? "Pull Sheet" : "Grocery List"
  end

  def sheet_title
    @single ? "NY Kitchen Pull Sheet" : "NY Kitchen Grocery List"
  end

  def plural(count, noun)
    "#{count} #{noun.pluralize(count)}"
  end
end
