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
end
