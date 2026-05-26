require "test_helper"

# The admin-only Super Agent usage/cost readout on /nykitchen/ask.
class KitchenSuperAgentUsageTest < ActionDispatch::IntegrationTest
  test "admins see the usage card with cost + tokens" do
    AiCallLog.create!(model: "claude-haiku-4-5", source: "nyk_agent", input_tokens: 1_000, output_tokens: 200)
    sign_in_as(User.create!(email_address: "sa-admin-#{SecureRandom.hex(4)}@example.com", role: "admin"))

    get "/nykitchen/ask"
    assert_response :success
    assert_match "Super Agent usage", @response.body
    assert_match "Full cost dashboard", @response.body
  end

  test "non-admins do not see the usage card" do
    sign_in_as(User.create!(email_address: "sa-user-#{SecureRandom.hex(4)}@example.com", role: "user"))

    get "/nykitchen/ask"
    assert_response :success
    assert_no_match "Super Agent usage", @response.body
  end
end
