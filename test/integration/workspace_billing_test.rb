require "test_helper"

class WorkspaceBillingTest < ActionDispatch::IntegrationTest
  setup do
    @owner  = User.create!(email_address: "wb-o-#{SecureRandom.hex(4)}@example.com")
    @viewer = User.create!(email_address: "wb-v-#{SecureRandom.hex(4)}@example.com")
    @admin  = User.create!(email_address: "wb-a-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @ws     = Workspace.create!(name: "Bill WS", owner: @owner)
    @ws.memberships.create!(user: @viewer, role: "viewer")
  end

  def log_usage(ws, input:, output:, model: "claude-haiku-4-5-20251001", source: "workspace_ai_assist")
    AiCallLog.create!(workspace: ws, source: source, model: model, input_tokens: input, output_tokens: output)
  end

  test "a workspace manager sees the billing page with this-month usage" do
    log_usage(@ws, input: 1000, output: 500)
    sign_in_as(@owner)
    get billing_workspace_path(@ws.slug)
    assert_response :success
    assert_match "AI usage", response.body
    assert_match "Social Agent drafts", response.body
  end

  test "a viewer cannot see billing" do
    sign_in_as(@viewer)
    get billing_workspace_path(@ws.slug)
    assert_redirected_to workspace_path(@ws.slug)
    assert_match(/owners and admins/i, flash[:alert])
  end

  test "a non-member cannot see billing" do
    stranger = User.create!(email_address: "wb-s-#{SecureRandom.hex(4)}@example.com")
    sign_in_as(stranger)
    get billing_workspace_path(@ws.slug)
    assert_redirected_to workspace_path(@ws.slug)
  end

  test "usage is scoped to the workspace (other workspaces excluded)" do
    other = Workspace.create!(name: "Other WS", owner: @owner)
    log_usage(@ws,  input: 1_000,    output: 500)
    log_usage(other, input: 9_000_000, output: 9_000_000, model: "claude-opus-4-8")

    sign_in_as(@owner)
    get billing_workspace_path(@ws.slug)
    assert_response :success
    # The big Opus spend from `other` (~$270) must not appear on this workspace.
    refute_match "$270", response.body
  end

  test "the NY Kitchen slug redirects to its dedicated billing page" do
    nyk = Workspace.create!(name: "NY Kitchen", owner: @owner, slug: "nykitchen")
    nyk # referenced
    sign_in_as(@owner)
    get billing_workspace_path("nykitchen")
    assert_redirected_to nyk_billing_path
  end

  test "site admin can set pricing; a non-admin manager cannot" do
    sign_in_as(@admin)
    @ws.memberships.create!(user: @admin, role: "admin")
    post billing_pricing_workspace_path(@ws.slug), params: { usage_multiplier: "3.0", base_fee_dollars: "25", discount_percent: "10" }
    assert_redirected_to billing_workspace_path(@ws.slug)
    @ws.reload
    assert_equal 3.0, @ws.usage_multiplier.to_f
    assert_equal 25.0, @ws.base_fee_dollars.to_f
    assert_equal 10.0, @ws.discount_percent.to_f

    # The workspace owner is a manager but NOT a site admin: pricing is blocked.
    sign_in_as(@owner)
    post billing_pricing_workspace_path(@ws.slug), params: { usage_multiplier: "9.0" }
    @ws.reload
    assert_equal 3.0, @ws.usage_multiplier.to_f, "owner (non-site-admin) must not change pricing"
  end
end
