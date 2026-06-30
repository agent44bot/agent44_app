require "test_helper"

# Covers the Social Agent flow redesign: breadcrumbs (generic workspaces always
# show the "Workspaces" root; NY Kitchen keeps the adaptive root so its pinned
# customers see NY Kitchen, not Workspaces), the People grouping (invite next to
# members), and the de-duplicated settings.
class WorkspaceTeamLayoutTest < ActionDispatch::IntegrationTest
  setup do
    @owner  = User.create!(email_address: "tl-o-#{SecureRandom.hex(4)}@example.com")
    @editor = User.create!(email_address: "tl-e-#{SecureRandom.hex(4)}@example.com")
    @ws     = Workspace.create!(name: "Layout WS", owner: @owner)
    @ws.memberships.create!(user: @editor, role: "editor")
  end

  # ----- adaptive breadcrumb root -----

  test "a generic single-workspace user gets the Workspaces crumb on the hub" do
    sign_in_as(@owner)
    get workspace_path(@ws.slug)
    assert_response :success
    assert_select "nav[aria-label=?] a[href=?]", "Breadcrumb", workspaces_path(force: 1)
  end

  test "a generic single-workspace user's social trail is Workspaces / Workspace / Social Agent" do
    sign_in_as(@owner)
    get social_workspace_path(@ws.slug)
    assert_response :success
    assert_select "nav[aria-label=?] a[href=?]", "Breadcrumb", workspaces_path(force: 1)
    assert_select "nav[aria-label=?] a[href=?]", "Breadcrumb", workspace_path(@ws.slug)
    assert_select "nav[aria-label=?] [aria-current=?]", "Breadcrumb", "page", text: "Social Agent"
  end

  test "a site admin gets the Workspaces crumb on the hub and the social page" do
    admin = User.create!(email_address: "tl-a-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @ws.memberships.create!(user: admin, role: "admin")
    sign_in_as(admin)

    get workspace_path(@ws.slug)
    assert_select "nav[aria-label=?] a[href=?]", "Breadcrumb", workspaces_path(force: 1)

    get social_workspace_path(@ws.slug)
    assert_select "nav[aria-label=?] a[href=?]", "Breadcrumb", workspaces_path(force: 1)
    assert_select "nav[aria-label=?] [aria-current=?]", "Breadcrumb", "page", text: "Social Agent"
  end

  # ----- People grouping + de-duplicated settings -----

  test "invite form sits directly under members with no settings in between" do
    sign_in_as(@owner)
    get workspace_path(@ws.slug)
    body = response.body

    members = body.index("Members")
    invite  = body.index("Invite a teammate")
    assert members, "Members heading should render"
    assert invite,  "Invite heading should render"
    assert invite > members, "Invite should come after Members"

    between = body[members...invite]
    %w[Brand\ logo Website\ URL Brand\ context Timezone].each do |h|
      refute_includes between, h, "#{h} should not sit between Members and Invite"
    end
  end

  test "the duplicate timezone form is gone from the social page but stays on the hub" do
    sign_in_as(@owner)
    get social_workspace_path(@ws.slug)
    assert_select "select[name=?]", "workspace[timezone]", false

    get workspace_path(@ws.slug)
    assert_select "select[name=?]", "workspace[timezone]"
  end

  test "an editor sees Members but not the invite form or danger zone" do
    sign_in_as(@editor)
    get workspace_path(@ws.slug)
    assert_response :success
    assert_includes response.body, "Members"
    assert_select "input[value=?]", "Send invite", false
    assert_select "input[value=?]", "Delete workspace", false
  end

  # ----- NY Kitchen adaptive root -----

  test "a NY Kitchen-only customer sees NY Kitchen as the root, not Workspaces" do
    nyk  = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @owner }
    lora = User.create!(email_address: "tl-lora-#{SecureRandom.hex(4)}@example.com")
    nyk.memberships.create!(user: lora, role: "admin")
    sign_in_as(lora)
    get nyk_social_path
    assert_response :success
    assert_select "nav[aria-label=?] a[href=?]", "Breadcrumb", nykitchen_path
    assert_select "nav[aria-label=?] a[href=?]", "Breadcrumb", workspaces_path(force: 1), false
  end

  test "a site admin sees Workspaces above NY Kitchen on the NYK social page" do
    nyk   = Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @owner }
    admin = User.create!(email_address: "tl-a2-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    nyk.memberships.create!(user: admin, role: "admin")
    sign_in_as(admin)
    get nyk_social_path
    assert_response :success
    assert_select "nav[aria-label=?] a[href=?]", "Breadcrumb", workspaces_path(force: 1)
    assert_select "nav[aria-label=?] a[href=?]", "Breadcrumb", nykitchen_path
  end
end
