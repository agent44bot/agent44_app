require "test_helper"

class UsageEventTest < ActiveSupport::TestCase
  setup do
    owner = User.create!(email_address: "ue-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @workspace = Workspace.create!(name: "NY Kitchen", owner: owner, slug: "nyk-#{SecureRandom.hex(3)}")
    @user = owner
  end

  test "record! logs a metered action defaulting to one penny" do
    event = UsageEvent.record!(workspace: @workspace, user: @user, kind: "report.on_demand")
    assert_equal "report.on_demand", event.kind
    assert_equal 1, event.unit_cents
    assert_equal 1, event.quantity
    assert_equal 1, event.cost_cents
    assert_equal({}, event.metadata)
  end

  test "metadata round-trips as JSON and cost_cents multiplies" do
    event = UsageEvent.record!(workspace: @workspace, user: @user, kind: "report.email",
                               quantity: 3, unit_cents: 2, metadata: { to: "board@example.com" })
    assert_equal "board@example.com", event.reload.metadata["to"]
    assert_equal 6, event.cost_cents
  end

  test "kind is required" do
    assert_raises(ActiveRecord::RecordInvalid) do
      UsageEvent.create!(workspace: @workspace, kind: nil)
    end
  end
end
