require "test_helper"

# Workspace helpers backing the cost-info dialogs: who counts as an owner, and
# the per-workspace flyer rate with its fallback to the app default.
class WorkspaceCostRateTest < ActiveSupport::TestCase
  setup do
    @owner  = User.create!(email_address: "own-#{SecureRandom.hex(4)}@example.com", role: "user")
    @ws     = Workspace.create!(slug: "ws-#{SecureRandom.hex(4)}", name: "WS", owner: @owner)
    @admin  = User.create!(email_address: "adm-#{SecureRandom.hex(4)}@example.com", role: "user")
    @editor = User.create!(email_address: "edt-#{SecureRandom.hex(4)}@example.com", role: "user")
    @site   = User.create!(email_address: "site-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @ws.memberships.create!(user: @admin,  role: "admin")
    @ws.memberships.create!(user: @editor, role: "editor")
  end

  test "owner? is the workspace owner or a site admin, not admins/editors" do
    assert @ws.owner?(@owner), "the workspace owner"
    assert @ws.owner?(@site),  "a site admin"
    assert_not @ws.owner?(@admin),  "a workspace admin is not an owner"
    assert_not @ws.owner?(@editor), "an editor is not an owner"
    assert_not @ws.owner?(nil)
  end

  test "effective_flyer_unit_cents falls back to the app default when unset" do
    assert_nil @ws.flyer_unit_cents
    assert_equal UsageEvent::FLYER_UNIT_CENTS, @ws.effective_flyer_unit_cents
    @ws.update!(flyer_unit_cents: 60)
    assert_equal 60, @ws.effective_flyer_unit_cents
  end

  test "AiCallLog.AGENT_SOURCES maps the AI agents to their billing sources" do
    assert_equal AiCallLog::LIST_AGENT_SOURCES, AiCallLog::AGENT_SOURCES["list"]
    assert_includes AiCallLog::AGENT_SOURCES["social"], "nyk_x_autopost"
    assert_nil AiCallLog::AGENT_SOURCES["display"], "Neon has no AI sources"
  end
end
