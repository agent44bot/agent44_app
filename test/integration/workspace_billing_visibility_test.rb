require "test_helper"

# The workspace AI usage / billing page must never expose raw cost or the
# usage multiplier to a workspace admin (a client). Only the owner and site
# admins see raw + the equation; admins see billed figures (raw x multiplier).
class WorkspaceBillingVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "bv-o-#{SecureRandom.hex(4)}@example.com")
    @admin = User.create!(email_address: "bv-a-#{SecureRandom.hex(4)}@example.com")
    @ws = Workspace.create!(name: "Bill WS", owner: @owner, usage_multiplier: 3.0)
    @ws.memberships.create!(user: @admin, role: "admin")
    # $0.10 raw (100k input tokens x $1/M on Haiku), billed = $0.30 at 3x.
    AiCallLog.create!(model: "claude-haiku-4-5-20251001", source: "workspace_ai_assist",
                      input_tokens: 100_000, output_tokens: 0, user: @owner, workspace: @ws)
  end

  test "owner sees raw cost and the multiplier equation" do
    sign_in_as(@owner)
    get billing_workspace_path(@ws.slug)
    assert_response :success
    assert_match(/raw/i, response.body)
    assert_includes response.body, "× 3.0"
    assert_includes response.body, "$0.1000" # raw per-feature cost
  end

  test "admin (client) sees billed figures, never raw or the multiplier" do
    sign_in_as(@admin)
    get billing_workspace_path(@ws.slug)
    assert_response :success
    assert_no_match(/raw/i, response.body)
    assert_not_includes response.body, "× 3.0"
    assert_not_includes response.body, "$0.1000"      # raw must not appear
    assert_includes response.body, "$0.3000"          # billed per-feature cost (0.10 x 3)
  end
end
