require "test_helper"

class Admin::FinanceControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin  = User.create!(email_address: "fin-admin-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @member = User.create!(email_address: "fin-member-#{SecureRandom.hex(4)}@example.com", role: "user")
  end

  test "redirects non-admins away from /admin/finance" do
    sign_in_as(@member)
    get "/admin/finance"
    assert_redirected_to workspaces_path
  end

  test "renders summary for admins with net profit and set-aside" do
    Expense.create!(incurred_on: Date.new(2026, 2, 1), vendor: "Fly.io", amount: 100, category: "Hosting", fingerprint: SecureRandom.hex)
    RevenueEntry.create!(received_on: Date.new(2026, 2, 1), source: "NY Kitchen", amount: 1100)

    sign_in_as(@admin)
    get admin_finance_path(year: 2026)
    assert_response :success
    assert_select "h1", text: /Agent44 Labs Finance/
    # net profit 1000, set-aside 30% = 300
    assert_match "$1,000.00", response.body
    assert_match "$300.00", response.body
  end

  test "shows the merged AI spend section" do
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 1_000_000, output_tokens: 0)
    sign_in_as(@admin)
    get admin_finance_path
    assert_response :success
    assert_select "h2", text: /AI spend this month/
    assert_match "nyk_enhance", response.body
  end

  test "import endpoint ingests an uploaded RocketMoney CSV" do
    csv = <<~CSV
      Date,Original Date,Name,Custom Name,Amount,Description,Category
      2026-02-25,2026-02-25,OpenRouter,,45.58,OpenRouter,Agent44Labs
    CSV
    file = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "rm.csv")

    sign_in_as(@admin)
    assert_difference -> { Expense.count }, 1 do
      post admin_finance_import_path, params: { file: file }
    end
    assert_redirected_to admin_finance_path(year: nil)
    assert_equal "Software/Subscriptions (COGS)", Expense.last.category
  end

  test "adds and removes revenue" do
    sign_in_as(@admin)
    assert_difference -> { RevenueEntry.count }, 1 do
      post admin_finance_revenues_path, params: { revenue_entry: { received_on: "2026-03-01", source: "NY Kitchen", amount: "500" } }
    end
    rev = RevenueEntry.last
    assert_difference -> { RevenueEntry.count }, -1 do
      delete admin_finance_revenue_path(rev)
    end
  end

  test "sorts expense line items by a whitelisted column and toggles direction" do
    Expense.create!(incurred_on: Date.new(2026, 3, 1), vendor: "Cheap Co", amount: 5, category: "Hosting", fingerprint: SecureRandom.hex)
    Expense.create!(incurred_on: Date.new(2026, 3, 2), vendor: "Pricey Co", amount: 500, category: "Hosting", fingerprint: SecureRandom.hex)
    sign_in_as(@admin)

    get admin_finance_path(year: 2026, sort: "amount", dir: "asc")
    assert_response :success
    assert_operator response.body.index("Cheap Co"), :<, response.body.index("Pricey Co")

    get admin_finance_path(year: 2026, sort: "amount", dir: "desc")
    assert_operator response.body.index("Pricey Co"), :<, response.body.index("Cheap Co")
  end

  test "ignores an unknown or malicious sort param and still renders" do
    Expense.create!(incurred_on: Date.new(2026, 3, 1), vendor: "Fly.io", amount: 10, category: "Hosting", fingerprint: SecureRandom.hex)
    sign_in_as(@admin)
    get admin_finance_path(year: 2026, sort: "amount); DROP TABLE expenses;--", dir: "sideways")
    assert_response :success
    assert_match "Fly.io", response.body
  end

  test "updating an expense can exclude it from totals" do
    e = Expense.create!(incurred_on: Date.new(2026, 1, 1), vendor: "NordVPN", amount: 92.28, category: "Software", fingerprint: SecureRandom.hex)
    sign_in_as(@admin)
    patch admin_finance_expense_path(e), params: { expense: { excluded: "1", category: "Software" } }
    assert e.reload.excluded
    assert_equal 0, Expense.year_total(2026)
  end
end
