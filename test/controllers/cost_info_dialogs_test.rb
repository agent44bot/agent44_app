require "test_helper"

# The (i) cost-info dialogs on the hub agent cards: managers (owner/admin) see
# the icon + a per-agent formula dialog; only the workspace owner may edit the
# flyer rate inside Neon's dialog. Editors/viewers see nothing.
class CostInfoDialogsTest < ActionDispatch::IntegrationTest
  setup do
    @owner  = User.create!(email_address: "own-#{SecureRandom.hex(4)}@example.com", role: "user")
    @ws     = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @owner }
    @admin  = User.create!(email_address: "adm-#{SecureRandom.hex(4)}@example.com", role: "user")
    @editor = User.create!(email_address: "edt-#{SecureRandom.hex(4)}@example.com", role: "user")
    @ws.memberships.find_or_create_by!(user: @admin)  { |m| m.role = "admin" }
    @ws.memberships.find_or_create_by!(user: @editor) { |m| m.role = "editor" }
    KitchenSnapshot.create!(taken_on: Date.current)
  end

  test "owner sees the (i) icons and an editable flyer rate form" do
    sign_in_as(@owner)
    get nykitchen_path
    assert_response :success
    assert_select ".ra-info", { minimum: 1 }, "manager sees cost-info triggers"
    assert_select "#cost-dialog-display",  1
    assert_select "#cost-dialog-list",     1
    # Owner gets the editable form, not the read-only text.
    assert_select "#cost-dialog-display form[action=?]", nyk_flyer_rate_path
    assert_select "#cost-dialog-display", text: /Only the workspace owner/, count: 0
    # Every dialog links to the billing page.
    assert_select "#cost-dialog-list a.cost-link"
  end

  test "workspace admin sees the dialogs but the rate is read-only" do
    sign_in_as(@admin)
    get nykitchen_path
    assert_response :success
    assert_select ".ra-info", minimum: 1
    assert_select "#cost-dialog-display", 1
    assert_select "#cost-dialog-display form[action=?]", nyk_flyer_rate_path, count: 0
    assert_select "#cost-dialog-display", text: /Only the workspace owner can change it/
  end

  test "editor sees no cost-info icons or dialogs" do
    sign_in_as(@editor)
    get nykitchen_path
    assert_response :success
    assert_select ".ra-info", count: 0
    assert_select "#cost-dialog-display", count: 0
  end

  test "owner can update the flyer rate; it persists as cents" do
    sign_in_as(@owner)
    patch nyk_flyer_rate_path, params: { flyer_rate_dollars: "0.55" }
    assert_redirected_to nykitchen_path
    assert_equal 55, @ws.reload.flyer_unit_cents
  end

  test "a non-owner admin cannot update the flyer rate" do
    sign_in_as(@admin)
    patch nyk_flyer_rate_path, params: { flyer_rate_dollars: "0.55" }
    assert_redirected_to nykitchen_path
    assert_nil @ws.reload.flyer_unit_cents, "admin write is rejected"
  end

  test "an out-of-range flyer rate is rejected" do
    sign_in_as(@owner)
    patch nyk_flyer_rate_path, params: { flyer_rate_dollars: "0" }
    assert_nil @ws.reload.flyer_unit_cents
    patch nyk_flyer_rate_path, params: { flyer_rate_dollars: "250" }
    assert_nil @ws.reload.flyer_unit_cents
  end

  test "the workspace rate drives new flyer usage events" do
    @ws.update!(flyer_unit_cents: 60)
    assert_difference -> { UsageEvent.of_kind(UsageEvent::FLYER_PRINT).count }, 1 do
      get nyk_display_print_path
    end
    assert_equal 60, UsageEvent.of_kind(UsageEvent::FLYER_PRINT).order(:id).last.unit_cents
  end

  test "billing page highlights the arriving agent's rows" do
    sign_in_as(@owner)
    get nyk_billing_path(agent: "list")
    assert_response :success
    assert_select "p", text: /Highlighting.*Sam.*features/m
    assert_select "a[href=?]", nyk_billing_path(anchor: "ai-usage"), text: /Show all/
  end

  test "an unknown billing agent param is ignored" do
    sign_in_as(@owner)
    get nyk_billing_path(agent: "bogus")
    assert_response :success
    assert_select "p", text: /Highlighting/, count: 0
  end
end
