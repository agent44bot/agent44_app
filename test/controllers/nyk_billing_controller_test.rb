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

  test "grocery list AI usage is itemized on the bill" do
    AiCallLog.create!(model: "claude-opus-4-8", source: "nyk_grocery_list",
                      input_tokens: 2_000, output_tokens: 4_000) # $0.11 raw
    sign_in_as(@admin)
    get "/nykitchen/billing"
    assert_response :success
    assert_match(/Grocery lists/, response.body)
    assert_match(/AI usage trend/, response.body)
  end

  test "customer Super Agent chat (nyk_ask) is billed, admin dogfood (nyk_agent) is not" do
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_ask",
                      input_tokens: 5_000, output_tokens: 2_000)
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_agent",
                      input_tokens: 9_999_999, output_tokens: 9_999_999) # huge dogfood, must be excluded
    sign_in_as(@admin)
    get "/nykitchen/billing"
    assert_response :success
    assert_match(/Super Agent chat/, response.body)
    assert_includes AiCallLog::NYK_SOURCES, "nyk_ask"
    refute_includes AiCallLog::NYK_SOURCES, "nyk_agent"
  end

  test "spend-by-model table breaks out Opus and Haiku with a total" do
    AiCallLog.create!(model: "claude-opus-4-8",           source: "nyk_grocery_list",
                      input_tokens: 1_000_000, output_tokens: 1_000_000) # $30
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_ask",
                      input_tokens: 1_000_000, output_tokens: 1_000_000) # $6
    sign_in_as(@admin)
    get "/nykitchen/billing"
    assert_response :success
    assert_match(/Spend by model/, response.body)
    assert_match(/Opus/,  response.body)
    assert_match(/Haiku/, response.body)
  end

  test "a manager can set a feature's model from billing" do
    sign_in_as(@admin)
    patch nyk_billing_model_path, params: { source: "nyk_grocery_list", model: "haiku" }
    assert_redirected_to nyk_billing_path
    assert_equal "claude-haiku-4-5-20251001",
                 AiModelChoice.resolve("nyk_grocery_list", default: "claude-opus-4-8")
  end

  test "update_model rejects an uncontrollable source or unknown model" do
    sign_in_as(@admin)
    patch nyk_billing_model_path, params: { source: "nyk_x_autopost", model: "haiku" }
    assert_nil Setting.get("ai_model:nyk_x_autopost")

    patch nyk_billing_model_path, params: { source: "nyk_grocery_list", model: "gpt" }
    assert_nil Setting.get("ai_model:nyk_grocery_list")
  end

  test "a non-manager cannot reach update_model" do
    sign_in_as(@user)
    patch nyk_billing_model_path, params: { source: "nyk_grocery_list", model: "haiku" }
    assert_redirected_to "/nykitchen"
    assert_nil Setting.get("ai_model:nyk_grocery_list")
  end

  test "unauthenticated request bounces to sign-in" do
    get "/nykitchen/billing"
    assert_redirected_to %r{/sign_in}
  end

  test "billing always shows the customer view (no Raw tab)" do
    sign_in_as(@admin)
    get "/nykitchen/billing"
    assert_response :success
    # The cost-basis "Raw monthly cost / No markup" copy is gone for everyone.
    refute_match(/Raw monthly cost/, response.body)
    refute_match(/No markup/, response.body)
    # Customer markup explainer is what's shown.
    assert_match(/3.* margin/, response.body)
  end

  test "?view=raw is ignored — still the customer view" do
    sign_in_as(@admin)
    get "/nykitchen/billing", params: { view: "raw" }
    assert_response :success
    refute_match(/No markup/, response.body)
    assert_match(/3.* margin/, response.body)
  end

  test "env override changes the customer total" do
    ENV["NYK_BASE_FEE_DOLLARS"] = "100"
    ENV["NYK_RAW_MULTIPLIER"]   = "5"
    begin
      sign_in_as(@admin)
      get "/nykitchen/billing"
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

  test "site admin can set flat fee, waive, and discount" do
    ws = Workspace.create!(name: "NY Kitchen", slug: "nykitchen", owner_id: @admin.id)
    sign_in_as(@admin)
    patch "/nykitchen/billing/pricing", params: { base_fee_dollars: "75", discount_percent: "10", base_fee_waived: "0" }
    ws.reload
    assert_in_delta 75.0, ws.base_fee_dollars.to_f, 0.001
    assert_equal 10, ws.discount_percent.to_i
    refute ws.base_fee_waived?
    assert_in_delta 75.0, ws.effective_base_fee, 0.001
  end

  test "waiving the fee zeroes the effective base fee" do
    ws = Workspace.create!(name: "NY Kitchen", slug: "nykitchen", owner_id: @admin.id)
    sign_in_as(@admin)
    patch "/nykitchen/billing/pricing", params: { base_fee_dollars: "75", base_fee_waived: "1" }
    assert ws.reload.base_fee_waived?
    assert_equal 0.0, ws.effective_base_fee
  end

  test "NYK workspace admin (Lora) cannot change customer pricing" do
    ws = Workspace.create!(name: "NY Kitchen", slug: "nykitchen", owner_id: @admin.id)
    ws.memberships.create!(user: @user, role: "admin")
    sign_in_as(@user)
    patch "/nykitchen/billing/pricing", params: { base_fee_dollars: "1", discount_percent: "99" }
    assert_redirected_to nyk_billing_path
    assert_nil ws.reload.base_fee_dollars
  end
end
