require "test_helper"

class InventoryItemTest < ActiveSupport::TestCase
  def item(**attrs)
    InventoryItem.create!({ name: "Test Wine", units_per_case: 12 }.merge(attrs))
  end

  test "on_hand sums in minus out" do
    i = item
    i.movements.create!(direction: "in",  quantity: 12)
    i.movements.create!(direction: "out", quantity: 5)
    assert_equal 7, i.on_hand
  end

  test "on_hand_by_item returns net per item in one query" do
    a = item(name: "A")
    b = item(name: "B")
    a.movements.create!(direction: "in",  quantity: 10)
    a.movements.create!(direction: "out", quantity: 3)
    b.movements.create!(direction: "in",  quantity: 6)
    map = InventoryItem.on_hand_by_item
    assert_equal 7, map[a.id]
    assert_equal 6, map[b.id]
  end

  test "find_by_code matches bottle and case barcodes, nil otherwise" do
    i = item(barcode: "111", case_barcode: "999")
    assert_equal i, InventoryItem.find_by_code("111")
    assert_equal i, InventoryItem.find_by_code("999")
    assert_nil InventoryItem.find_by_code("000")
    assert_nil InventoryItem.find_by_code("")
  end

  test "units_for_code: case code is a full case, anything else is one" do
    i = item(barcode: "111", case_barcode: "999", units_per_case: 12)
    assert_equal 12, i.units_for_code("999")
    assert_equal 1,  i.units_for_code("111")
    assert_equal 1,  i.units_for_code("unknown")
  end

  test "low_stock? only when par is set and on_hand is at or below it" do
    i = item(par_level: 6)
    i.movements.create!(direction: "in", quantity: 6)
    assert i.reload.low_stock?
    i.movements.create!(direction: "in", quantity: 1) # now 7 > 6
    refute i.reload.low_stock?

    no_par = item(name: "No par", par_level: nil)
    assert_equal 0, no_par.on_hand
    refute no_par.low_stock?
  end

  test "blank barcodes normalize to nil and many can coexist" do
    a = item(name: "A", barcode: "")
    b = item(name: "B", barcode: "  ")
    assert_nil a.barcode
    assert_nil b.barcode
    assert a.persisted?
    assert b.persisted?
  end

  test "a duplicate present barcode is rejected" do
    item(barcode: "555")
    dup = InventoryItem.new(name: "Dup", barcode: "555", units_per_case: 12)
    refute dup.valid?
  end
end
