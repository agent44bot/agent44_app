require "test_helper"
require "zip"
require "ostruct"

class KitchenGroceryXlsxTest < ActiveSupport::TestCase
  Event  = Struct.new(:name, :start_at)
  Packet = Struct.new(:equipment)

  def result_double(ok: true)
    OpenStruct.new(
      categories: [
        { "name" => "Produce",  "items" => [ { "item" => "Yellow onion", "quantity" => "3 lb", "price" => 4.5 } ] },
        { "name" => "Proteins", "items" => [ { "item" => "Chicken thigh", "quantity" => "5 lb", "price" => 18.0 } ] }
      ],
      to_taste: %w[salt pepper]
    ).tap { |o| o.define_singleton_method(:ok?) { ok } }
  end

  # All visible cell text in the workbook: caxlsx stores strings inline (t="s"
  # -> sharedStrings), so reading that entry is enough to assert on content.
  def workbook_text(data)
    text = +""
    Zip::File.open_buffer(StringIO.new(data)) do |zip|
      zip.each do |entry|
        next unless entry.name.end_with?(".xml")
        text << entry.get_input_stream.read
      end
    end
    text
  end

  def with_recipe
    [
      { event: Event.new("Knife Skills", Time.zone.local(2026, 7, 12, 18)), headcount: 12, stations: 3,
        packet: Packet.new([ "Chef knife", "Cutting board" ]) },
      { event: Event.new("Pasta Night", Time.zone.local(2026, 7, 13, 18)), headcount: 8, stations: 2,
        packet: Packet.new([]) }
    ]
  end

  def build(**over)
    KitchenGroceryXlsx.new(**{
      result: result_double, with_recipe: with_recipe,
      range: Date.new(2026, 7, 12)..Date.new(2026, 7, 18),
      total_headcount: 20, single: false, single_event: nil, show_prices: true
    }.merge(over)).render
  end

  test "renders a valid (zip-magic) xlsx byte string" do
    data = build
    assert data.is_a?(String)
    assert data.bytesize.positive?
    assert_equal "PK".b, data.byteslice(0, 2).b, "xlsx is a zip, starts with PK"
  end

  test "the workbook includes the class names and dates" do
    text = workbook_text(build)
    assert_includes text, "Classes in this list"
    assert_includes text, "Knife Skills"
    assert_includes text, "Sun Jul 12"
    assert_includes text, "Pasta Night"
    # Grocery + equipment sections carry through.
    assert_includes text, "Yellow onion"
    assert_includes text, "Equipment per station"
    assert_includes text, "Chef knife"
  end

  test "single-class pull sheet skips the classes table (header already names it)" do
    ev = Event.new("Knife Skills", Time.zone.local(2026, 7, 12, 18))
    text = workbook_text(build(single: true, single_event: ev, with_recipe: [ with_recipe.first ], show_prices: false))
    assert_includes text, "NY Kitchen Pull Sheet"
    assert_includes text, "Knife Skills"
    assert_not_includes text, "Classes in this list"
  end
end
