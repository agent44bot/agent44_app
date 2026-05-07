require "test_helper"

class NykBillingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = User.create!(email_address: "nyk-bill-admin-#{SecureRandom.hex(4)}@example.com",  role: "admin")
    @kitchen  = User.create!(email_address: "nyk-bill-kc-#{SecureRandom.hex(4)}@example.com",     role: "kitchen_customer")
    @member   = User.create!(email_address: "nyk-bill-member-#{SecureRandom.hex(4)}@example.com", role: "member")
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 1_500, output_tokens: 800)
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_x_autopost",
                      input_tokens: 300,   output_tokens: 100)
  end

  teardown { ENV.delete("NYK_BILLING_VISIBLE") }

  test "admin always sees /nykitchen/billing regardless of flag" do
    ENV["NYK_BILLING_VISIBLE"] = nil
    sign_in_as(@admin)
    get "/nykitchen/billing"
    assert_response :success
    assert_match(/Total this month/i, response.body)
  end

  test "kitchen_customer is redirected when flag is unset" do
    ENV["NYK_BILLING_VISIBLE"] = nil
    sign_in_as(@kitchen)
    get "/nykitchen/billing"
    assert_redirected_to "/nykitchen"
  end

  test "kitchen_customer sees /nykitchen/billing once the flag is true" do
    ENV["NYK_BILLING_VISIBLE"] = "true"
    sign_in_as(@kitchen)
    get "/nykitchen/billing"
    assert_response :success
  end

  test "non-kitchen, non-admin user is redirected even with the flag" do
    ENV["NYK_BILLING_VISIBLE"] = "true"
    sign_in_as(@member)
    get "/nykitchen/billing"
    assert_redirected_to "/nykitchen"
  end

  test "unauthenticated request bounces to sign-in" do
    get "/nykitchen/billing"
    assert_redirected_to %r{/session/new}
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
end
