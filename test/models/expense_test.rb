require "test_helper"

class ExpenseTest < ActiveSupport::TestCase
  test "fingerprint is stable and case-insensitive on vendor/description" do
    a = Expense.fingerprint_for(incurred_on: Date.new(2026, 1, 1), vendor: "DNSimple", amount: 6.5, raw_description: "DNSIMPLE")
    b = Expense.fingerprint_for(incurred_on: Date.new(2026, 1, 1), vendor: "dnsimple", amount: 6.50, raw_description: "dnsimple")
    assert_equal a, b
  end

  test "tax_year is derived from incurred_on" do
    e = Expense.create!(incurred_on: Date.new(2026, 3, 2), vendor: "Fly.io", amount: 16.03,
                        fingerprint: SecureRandom.hex)
    assert_equal 2026, e.tax_year
  end

  test "category_totals and year_total exclude rows marked excluded" do
    Expense.create!(incurred_on: Date.new(2026, 1, 1), vendor: "OpenRouter", amount: 10, category: "Software", fingerprint: SecureRandom.hex)
    Expense.create!(incurred_on: Date.new(2026, 1, 2), vendor: "DNSimple", amount: 5, category: "Domains/Web", fingerprint: SecureRandom.hex)
    Expense.create!(incurred_on: Date.new(2026, 1, 3), vendor: "YouTube", amount: 99, category: "Software", excluded: true, fingerprint: SecureRandom.hex)

    assert_equal 15, Expense.year_total(2026)
    totals = Expense.category_totals(2026).to_h
    assert_equal 10, totals["Software"]
    assert_equal 5, totals["Domains/Web"]
  end
end
