require "test_helper"

class Finance::RocketMoneyImporterTest < ActiveSupport::TestCase
  CSV_TEXT = <<~CSV
    Date,Original Date,Name,Custom Name,Amount,Description,Category
    2026-02-25,2026-02-25,OpenRouter,,45.58,OpenRouter,Agent44Labs
    2026-02-28,2026-02-28,Youtube Premium,,82.99,,Agent44Labs
    2026-02-14,2026-02-14,Mac Mini Agents,Mac Mini Agent44,592.92,,Agent44Labs
    2026-03-01,2026-03-01,Groceries,,50.00,,Personal
  CSV

  test "imports only business-category rows and categorizes them" do
    result = Finance::RocketMoneyImporter.new(CSV_TEXT).import!

    assert_equal 3, result.imported, "should skip the Personal row"
    assert_equal 0, result.skipped

    openrouter = Expense.find_by(vendor: "OpenRouter")
    assert_equal "Software/Subscriptions (COGS)", openrouter.category

    youtube = Expense.find_by!(vendor: "YouTube Premium")
    assert youtube.excluded, "YouTube should be excluded by default"
  end

  test "year totals exclude the excluded YouTube row" do
    Finance::RocketMoneyImporter.new(CSV_TEXT).import!
    # 45.58 + 592.92, YouTube excluded
    assert_equal 638.50, Expense.year_total(2026)
  end

  test "re-importing the same file skips duplicates" do
    Finance::RocketMoneyImporter.new(CSV_TEXT).import!
    second = Finance::RocketMoneyImporter.new(CSV_TEXT).import!
    assert_equal 0, second.imported
    assert_equal 3, second.skipped
  end

  test "flags rows that need review or carry a note" do
    result = Finance::RocketMoneyImporter.new(CSV_TEXT).import!
    # Mac mini (Section 179 note) + YouTube (excluded note)
    assert_equal 2, result.flagged
  end

  test "raises a friendly error on malformed CSV" do
    assert_raises(ArgumentError) do
      Finance::RocketMoneyImporter.new("\"unterminated").import!
    end
  end
end
