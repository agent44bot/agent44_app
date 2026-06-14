require "test_helper"

class Finance::ExpenseCategorizerTest < ActiveSupport::TestCase
  C = Finance::ExpenseCategorizer

  test "maps known vendors to category and purpose" do
    assert_equal "Domains/Web", C.categorize("DNSIMPLE")[:category]
    assert_equal "Hosting", C.categorize("Fly.io")[:category]
    assert_equal "Software/Subscriptions (COGS)", C.categorize("OpenRouter")[:category]
    assert_equal "Equipment", C.categorize("Mac Mini Agent44")[:category]
    assert_equal "Contract labor", C.categorize("CASH APP*VIOLET")[:category]
    assert_equal "Education/Conferences", C.categorize("SYR UNIV EVENTS")[:category]
  end

  test "Anthropic and Claude both map to software" do
    assert_equal "Software/Subscriptions", C.categorize("ANTHROPIC* CLAUDE SUB")[:category]
    assert_equal "Software/Subscriptions", C.categorize("CLAUDE.AI SUBSCRIPTION")[:category]
  end

  test "known-personal vendors are excluded by default" do
    assert C.categorize("Youtube Premium")[:excluded]
    assert C.categorize("NordVpn")[:excluded]
  end

  test "unknown vendors fall through to uncategorized and flagged" do
    result = C.categorize("Some Random Vendor", "Some Random Vendor")
    assert_equal "Uncategorized", result[:category]
    assert_equal "Some Random Vendor", result[:vendor]
    assert_equal "Needs review", result[:review_flag]
  end
end
