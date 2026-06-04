require "test_helper"

# End-to-end: the site-admin "Show billing to members" toggle gates whether
# workspace members see $ amounts on the NYK agents hub.
#
# Three actors:
#   - admin       (site admin, e.g. Rich) — always sees billing, can flip toggle
#   - member      (non-manager workspace member, role "editor") — sees billing
#                 iff toggle is on. Managers (owner/admin, e.g. Lora) always
#                 see billing via Workspace#manager?, so they are not gated.
#   - outsider    (signed-in user with no NYK membership) — never sees billing
class BillingVisibilityToggleTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = User.create!(email_address: "biz-admin-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @member   = User.create!(email_address: "biz-lora-#{SecureRandom.hex(4)}@example.com",  role: "user")
    @outsider = User.create!(email_address: "biz-out-#{SecureRandom.hex(4)}@example.com",   role: "user")

    @nyk = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @admin }
    @nyk.memberships.find_or_create_by!(user: @admin) { |m| m.role = "owner" }
    @nyk.memberships.find_or_create_by!(user: @member) { |m| m.role = "editor" }
    @nyk.update!(pricing_visible_to_members: false)

    # A few smoke runs with cost so $ amounts have something to render.
    3.times do |i|
      SmokeTestRun.create!(name: "nyk_calendar_nav", status: "passed",
                           started_at: i.hours.ago, duration_ms: 30_000, cost_dollars: 0.0003)
    end
  end

  test "toggle defaults to off: member does NOT see $ on the NYK hub" do
    sign_in_as(@member)
    get nykitchen_path
    assert_response :success
    refute_match(/\$\d/, hub_card_for(:test, response.body),
                 "Test Agent card should not show $ when toggle is off")
  end

  test "site admin always sees $ regardless of toggle" do
    @nyk.update!(pricing_visible_to_members: false)
    sign_in_as(@admin)
    get nykitchen_path
    assert_match(/\$\d/, hub_card_for(:test, response.body),
                 "Admin should see $ even when toggle is off")
  end

  test "outsider never sees $ even when toggle is on" do
    @nyk.update!(pricing_visible_to_members: true)
    sign_in_as(@outsider)
    get nykitchen_path
    refute_match(/\$\d/, hub_card_for(:test, response.body),
                 "Non-member should not see $ regardless of the toggle")
  end

  test "flipping the toggle on lets the member see $; flipping off hides it again" do
    sign_in_as(@admin)
    post toggle_pricing_workspace_path(@nyk.slug)
    assert @nyk.reload.pricing_visible_to_members?, "Toggle should flip on"

    sign_in_as(@member)
    get nykitchen_path
    assert_match(/\$\d/, hub_card_for(:test, response.body),
                 "Member should see $ after toggle flipped on")

    sign_in_as(@admin)
    post toggle_pricing_workspace_path(@nyk.slug)
    refute @nyk.reload.pricing_visible_to_members?, "Toggle should flip off"

    sign_in_as(@member)
    get nykitchen_path
    refute_match(/\$\d/, hub_card_for(:test, response.body),
                 "Member should not see $ after toggle flipped back off")
  end

  test "non-site-admin member cannot flip the toggle" do
    sign_in_as(@member)
    post toggle_pricing_workspace_path(@nyk.slug)
    refute @nyk.reload.pricing_visible_to_members?,
           "Workspace admin (non-site-admin) should not be able to flip the toggle"
    assert_redirected_to workspaces_path
  end

  private

  # Crude slice: from the Test card's classification tag ("Sentry") to the end
  # of the document so we're asserting on just that one card, not the whole page
  # (which has other prices like the running rate footer).
  def hub_card_for(agent, body)
    case agent
    when :test
      # Test (Argus · Sentry) is the last card; grep from its classification
      # tag to end-of-document so the regex doesn't depend on card-ordering.
      body[/Sentry.*\z/m].to_s
    end
  end
end
