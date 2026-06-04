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

  test "non-admin NYK members do not see the usage card" do
    # /nykitchen/ask 404s for non-members, so the non-admin needs an NYK
    # membership (non-manager role) to reach the page at all.
    owner = User.create!(email_address: "sa-own-#{SecureRandom.hex(4)}@example.com", role: "admin")
    nyk = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = owner }
    user = User.create!(email_address: "sa-user-#{SecureRandom.hex(4)}@example.com", role: "user")
    nyk.memberships.find_or_create_by!(user: user) { |m| m.role = "editor" }
    sign_in_as(user)

    get "/nykitchen/ask"
    assert_response :success
    assert_no_match "Super Agent usage", @response.body
  end

  test "outsiders get a 404 on the ask page" do
    sign_in_as(User.create!(email_address: "sa-out-#{SecureRandom.hex(4)}@example.com", role: "user"))

    get "/nykitchen/ask"
    assert_response :not_found
  end
end
