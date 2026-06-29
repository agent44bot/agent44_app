require "test_helper"

# Covers the Social Agent flow redesign: breadcrumbs, the People grouping
# (invite next to members), and the de-duplicated settings.
class WorkspaceTeamLayoutTest < ActionDispatch::IntegrationTest
  setup do
    @owner  = User.create!(email_address: "tl-o-#{SecureRandom.hex(4)}@example.com")
    @editor = User.create!(email_address: "tl-e-#{SecureRandom.hex(4)}@example.com")
    @ws     = Workspace.create!(name: "Layout WS", owner: @owner)
    @ws.memberships.create!(user: @editor, role: "editor")
  end

  test "hub renders a breadcrumb trail to Workspaces" do
    sign_in_as(@owner)
    get workspace_path(@ws.slug)
    assert_response :success
    assert_select "nav[aria-label=?]", "Breadcrumb"
    assert_select "nav[aria-label=?] a[href=?]", "Breadcrumb", workspaces_path(force: 1)
    assert_select "nav[aria-label=?] [aria-current=?]", "Breadcrumb", "page", text: @ws.name
  end

  test "social page renders a breadcrumb with Social Agent as the current page" do
    sign_in_as(@owner)
    get social_workspace_path(@ws.slug)
    assert_response :success
    assert_select "nav[aria-label=?] a[href=?]", "Breadcrumb", workspace_path(@ws.slug)
    assert_select "nav[aria-label=?] [aria-current=?]", "Breadcrumb", "page", text: "Social Agent"
  end

  test "invite form sits directly under members with no settings in between" do
    sign_in_as(@owner)
    get workspace_path(@ws.slug)
    body = response.body

    members = body.index("Members")
    invite  = body.index("Invite a teammate")
    assert members, "Members heading should render"
    assert invite,  "Invite heading should render"
    assert invite > members, "Invite should come after Members"

    # No workspace-settings heading should appear between Members and Invite.
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

  test "NY Kitchen social page uses its own breadcrumb root, not Workspaces" do
    nyk = Workspace.create!(name: "NY Kitchen", owner: @owner, slug: "nykitchen")
    nyk # referenced
    sign_in_as(@owner)
    get nyk_social_path
    assert_response :success
    assert_select "nav[aria-label=?] a[href=?]", "Breadcrumb", nykitchen_path
    assert_select "nav[aria-label=?] a[href=?]", "Breadcrumb", workspaces_path(force: 1), false
  end
end
