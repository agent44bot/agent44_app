require "test_helper"

class NykBillingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "nyk-bill-admin-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @user  = User.create!(email_address: "nyk-bill-user-#{SecureRandom.hex(4)}@example.com",  role: "user")
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 1_500, output_tokens: 800)
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_x_autopost",
                      input_tokens: 300,   output_tokens: 100)
  end

  test "admin sees /nykitchen/billing" do
    sign_in_as(@admin)
    get "/nykitchen/billing"
    assert_response :success
    assert_match(/Total this month/i, response.body)
  end

  test "non-admin is redirected to /nykitchen" do
    sign_in_as(@user)
    get "/nykitchen/billing"
    assert_redirected_to "/nykitchen"
  end

  test "unauthenticated request bounces to sign-in" do
    get "/nykitchen/billing"
    assert_redirected_to %r{/sign_in}
  end

  test "raw view (default) shows raw fleet cost" do
    sign_in_as(@admin)
    get "/nykitchen/billing"
    assert_response :success
    # Raw fleet cost on this dataset is essentially $0 — no big totals shown
    refute_match(/\$50\.00/, response.body)
    assert_match(/Raw monthly cost/, response.body)
  end

  test "customer view applies $50 + 3x markup" do
    sign_in_as(@admin)
    get "/nykitchen/billing", params: { view: "customer" }
    assert_response :success
    # Base fee shows in the explainer
    assert_match(/\$50/, response.body)
    # Markup phrasing
    assert_match(/3.* margin/, response.body)
  end

  test "env override changes the customer total" do
    ENV["NYK_BASE_FEE_DOLLARS"] = "100"
    ENV["NYK_RAW_MULTIPLIER"]   = "5"
    begin
      sign_in_as(@admin)
      get "/nykitchen/billing", params: { view: "customer" }
      assert_response :success
      assert_match(/\$100/, response.body)
      assert_match(/5.* margin/, response.body)
    ensure
      ENV.delete("NYK_BASE_FEE_DOLLARS")
      ENV.delete("NYK_RAW_MULTIPLIER")
    end
  end

  test "NYK workspace admin (not a global admin) can see billing" do
    ws = Workspace.create!(name: "NY Kitchen", slug: "nykitchen", owner_id: @admin.id)
    ws.memberships.create!(user: @user, role: "admin")
    sign_in_as(@user)
    get "/nykitchen/billing"
    assert_response :success
  end

  test "NYK workspace editor cannot see billing" do
    ws = Workspace.create!(name: "NY Kitchen", slug: "nykitchen", owner_id: @admin.id)
    ws.memberships.create!(user: @user, role: "editor")
    sign_in_as(@user)
    get "/nykitchen/billing"
    assert_redirected_to "/nykitchen"
  end

  test "site admin can set the test-run rate and it re-prices existing runs" do
    ws  = Workspace.create!(name: "NY Kitchen", slug: "nykitchen", owner_id: @admin.id)
    run = SmokeTestRun.create!(name: "nyk_calendar_nav", status: "passed", started_at: Time.current, duration_ms: 60_000)
    sign_in_as(@admin)
    patch "/nykitchen/billing/rate", params: { test_cost_per_minute: "0.044" }
    assert_redirected_to nyk_billing_path
    assert_in_delta 0.044, ws.reload.test_cost_per_minute.to_f, 0.0001
    assert_in_delta 0.044, run.reload.cost_dollars.to_f, 0.0001 # 1 min × $0.044
  end

  test "NYK workspace admin (Lora) cannot change the rate" do
    ws = Workspace.create!(name: "NY Kitchen", slug: "nykitchen", owner_id: @admin.id)
    ws.memberships.create!(user: @user, role: "admin")
    sign_in_as(@user)
    patch "/nykitchen/billing/rate", params: { test_cost_per_minute: "0.99" }
    assert_redirected_to nyk_billing_path
    assert_nil ws.reload.test_cost_per_minute
  end
end
