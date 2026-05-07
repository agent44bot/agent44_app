require "test_helper"

class Admin::AiCostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin  = User.create!(email_address: "ai-costs-admin-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @member = User.create!(email_address: "ai-costs-member-#{SecureRandom.hex(4)}@example.com", role: "member")
  end

  test "redirects non-admin away from /admin/ai_costs" do
    sign_in_as(@member)
    get "/admin/ai_costs"
    assert_redirected_to root_path
  end

  test "renders for admins, surfaces NYK subtotal and recent rows" do
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_enhance",
                      input_tokens: 1_000_000, output_tokens: 0)
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "nyk_x_autopost",
                      input_tokens: 0, output_tokens: 200_000)
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "other_feature",
                      input_tokens: 100_000, output_tokens: 0)

    sign_in_as(@admin)
    get "/admin/ai_costs"

    assert_response :success
    assert_select "h1", text: /AI Costs/
    # NYK subtotal: $1.00 (input) + $1.00 (output) = $2.00, no third row
    assert_match(/2\.0000/, response.body)
    # Source labels appear in the breakdown table
    assert_match "nyk_enhance",     response.body
    assert_match "nyk_x_autopost",  response.body
    assert_match "other_feature",   response.body
  end
end
