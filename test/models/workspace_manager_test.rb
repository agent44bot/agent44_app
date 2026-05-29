require "test_helper"

class WorkspaceManagerTest < ActiveSupport::TestCase
  def user(role = "user")
    User.create!(email_address: "wm-#{SecureRandom.hex(4)}@example.com", role: role)
  end

  setup do
    @site_admin = user("admin")
    @owner      = user
    @ws = Workspace.create!(name: "WS", slug: "wm-#{SecureRandom.hex(4)}", owner_id: @owner.id)
    @editor = user
    @ws.memberships.create!(user: @editor, role: "editor")
    @stranger = user
  end

  test "manager? is true for site admin, workspace owner, and workspace admin" do
    assert @ws.manager?(@site_admin), "site admin"
    assert @ws.manager?(@owner), "workspace owner"
    ws_admin = user
    @ws.memberships.create!(user: ws_admin, role: "admin")
    assert @ws.manager?(ws_admin), "workspace admin"
  end

  test "manager? is false for editor, viewer, non-member, and nil" do
    refute @ws.manager?(@editor), "editor"
    viewer = user
    @ws.memberships.create!(user: viewer, role: "viewer")
    refute @ws.manager?(viewer), "viewer"
    refute @ws.manager?(@stranger), "non-member"
    refute @ws.manager?(nil), "nil"
  end

  test "pricing_visible_for? follows manager? when the members toggle is off" do
    refute @ws.pricing_visible_to_members?
    assert @ws.pricing_visible_for?(@owner)
    assert @ws.pricing_visible_for?(@site_admin)
    refute @ws.pricing_visible_for?(@editor)
    refute @ws.pricing_visible_for?(@stranger)
  end

  test "effective_test_rate falls back to the default and honors an override" do
    assert_equal SmokeTestRun::COST_PER_MINUTE, @ws.effective_test_rate
    @ws.update!(test_cost_per_minute: 0.044)
    assert_in_delta 0.044, @ws.effective_test_rate.to_f, 0.0001
  end
end
