require "test_helper"

class WorkspacesTest < ActionDispatch::IntegrationTest
  setup do
    @owner   = User.create!(email_address: "ws-o-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @viewer  = User.create!(email_address: "ws-v-#{SecureRandom.hex(4)}@example.com")
    @outside = User.create!(email_address: "ws-x-#{SecureRandom.hex(4)}@example.com")
  end

  test "GET /workspaces requires sign-in" do
    get workspaces_path
    assert_redirected_to %r{/sign_in}
  end

  test "non-admin with one workspace lands directly in it" do
    member = User.create!(email_address: "solo-#{SecureRandom.hex(4)}@example.com", role: "user")
    ws = Workspace.create!(name: "Solo", owner: @owner)
    ws.memberships.create!(user: member, role: "editor")

    sign_in_as(member)
    get workspaces_path
    assert_redirected_to workspace_path(ws.slug)
  end

  test "force=1 lets a single-workspace member still see the list" do
    member = User.create!(email_address: "solo-#{SecureRandom.hex(4)}@example.com", role: "user")
    ws = Workspace.create!(name: "Solo", owner: @owner)
    ws.memberships.create!(user: member, role: "editor")

    sign_in_as(member)
    get workspaces_path(force: 1)
    assert_response :success
    assert_match ws.name, response.body
  end

  test "site admin with one workspace still sees the list" do
    Workspace.create!(name: "Only", owner: @owner)
    sign_in_as(@owner)
    get workspaces_path
    assert_response :success
  end

  test "user sees only workspaces they're a member of" do
    mine   = Workspace.create!(name: "Mine",   owner: @owner)
    theirs = Workspace.create!(name: "Theirs", owner: @outside)

    sign_in_as(@owner)
    get workspaces_path
    assert_response :success
    assert_match mine.name,   response.body
    refute_match theirs.name, response.body
  end

  test "index renders trashcan for owners/admins and hides it from viewers" do
    owned   = Workspace.create!(name: "OwnedWS",  owner: @owner)
    guested = Workspace.create!(name: "GuestedWS", owner: @outside)
    guested.memberships.create!(user: @owner, role: "viewer")

    sign_in_as(@owner)
    get workspaces_path
    body = response.body
    assert_match %r{action="/workspaces/#{owned.slug}".*name="_method" value="delete"}m, body,
      "owner should see a delete form for their own workspace"
    refute_match %r{action="/workspaces/#{guested.slug}".*name="_method" value="delete"}m, body,
      "viewer role should NOT see a delete form"
  end

  test "POST /workspaces creates one and makes you owner" do
    sign_in_as(@owner)
    assert_difference -> { Workspace.count }, 1 do
      post workspaces_path, params: { workspace: { name: "Brand New", description: "hi", timezone: "Eastern Time (US & Canada)" } }
    end
    ws = Workspace.order(:created_at).last
    assert_redirected_to social_workspace_path(ws.slug)
    assert_equal "owner", ws.role_for(@owner)
  end

  test "slug auto-dedupes" do
    sign_in_as(@owner)
    post workspaces_path, params: { workspace: { name: "Magenta", timezone: "UTC" } }
    post workspaces_path, params: { workspace: { name: "Magenta", timezone: "UTC" } }
    slugs = Workspace.where(name: "Magenta").pluck(:slug).sort
    assert_equal [ "magenta", "magenta-2" ], slugs
  end

  test "non-member cannot view a workspace" do
    ws = Workspace.create!(name: "Private", owner: @outside)
    sign_in_as(@owner)
    get workspace_path(ws.slug)
    assert_redirected_to workspaces_path
    follow_redirect!
    assert_match "not a member", response.body
  end

  test "viewer cannot delete a workspace" do
    ws = Workspace.create!(name: "Keep", owner: @owner)
    ws.memberships.create!(user: @viewer, role: "viewer")
    sign_in_as(@viewer)
    delete workspace_path(ws.slug)
    assert Workspace.exists?(ws.id), "workspace should still exist"
    assert_response :redirect
  end

  test "owner can delete a workspace and cascades through dependents" do
    ws = Workspace.create!(name: "Doomed", owner: @owner)
    ws.memberships.create!(user: @viewer, role: "viewer")
    ws.invitations.create!(invited_by: @owner, email: "x@example.com", role: "editor")
    acct = ws.social_accounts.create!(platform: "x", connected_by: @owner, handle: "@d", external_id: "1",
      access_token: "t", refresh_token: "r", token_expires_at: 1.hour.from_now, status: "active")
    ws.workspace_posts.create!(author: @owner, social_account: acct, platform: "x",
      body: "hi", status: "posted", remote_id: "1", posted_at: Time.current)

    sign_in_as(@owner)
    delete workspace_path(ws.slug)
    assert_redirected_to workspaces_path

    refute Workspace.exists?(ws.id)
    assert_equal 0, WorkspaceMembership.where(workspace_id: ws.id).count
    assert_equal 0, WorkspaceInvitation.where(workspace_id: ws.id).count
    assert_equal 0, SocialAccount.where(workspace_id: ws.id).count
    assert_equal 0, WorkspacePost.where(workspace_id: ws.id).count
  end

  test "workspace-admin (non-owner) cannot delete the workspace" do
    # Deleting is owner-only: an admin (e.g. a customer contact) manages the
    # team and content but must not be able to delete the workspace.
    ws = Workspace.create!(name: "AdminDoomed", owner: @owner)
    admin = User.create!(email_address: "ws-a-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    ws.memberships.create!(user: admin, role: "admin")
    sign_in_as(admin)
    delete workspace_path(ws.slug)
    assert_redirected_to workspace_path(ws.slug)
    assert Workspace.exists?(ws.id), "an admin must not be able to delete the workspace"
  end

  test "admin can update timezone inline" do
    ws = Workspace.create!(name: "TZWS", owner: @owner, timezone: "UTC")
    sign_in_as(@owner)
    patch workspace_path(ws.slug), params: { workspace: { timezone: "Eastern Time (US & Canada)" } }
    assert_redirected_to social_workspace_path(ws.slug)
    assert_equal "Eastern Time (US & Canada)", ws.reload.timezone
  end

  test "viewer cannot update timezone" do
    ws = Workspace.create!(name: "TZNo", owner: @owner, timezone: "UTC")
    ws.memberships.create!(user: @viewer, role: "viewer")
    sign_in_as(@viewer)
    patch workspace_path(ws.slug), params: { workspace: { timezone: "Eastern Time (US & Canada)" } }
    assert_equal "UTC", ws.reload.timezone
  end

  # --- Workspace agents hub --------------------------------------------------

  test "show renders a workspace hub with a Social Agent card" do
    ws = Workspace.create!(name: "Hub WS", owner: @owner)
    sign_in_as(@owner)
    get workspace_path(ws.slug)
    assert_response :success
    assert_match /Social Agent/,       response.body
    assert_match /No platforms connected yet/, response.body
    # Hub links to the social composer, not back to itself.
    assert_match %r{href="/workspaces/#{ws.slug}/social"}, response.body
  end

  test "show 301-redirects ny-kitchen to /nykitchen so there's one NYK destination" do
    ws = Workspace.create!(name: "NY Kitchen", owner: @owner, slug: "nykitchen")
    sign_in_as(@owner)
    get workspace_path(ws.slug)
    assert_redirected_to nykitchen_path
    assert_equal 301, response.status
  end

  test "site admin can toggle pricing visibility on a workspace" do
    ws = Workspace.create!(name: "Toggle WS", owner: @owner)
    sign_in_as(@owner)
    refute ws.pricing_visible_to_members?
    assert_difference -> { ws.reload.pricing_visible_to_members? ? 1 : 0 }, 1 do
      post toggle_pricing_workspace_path(ws.slug)
    end
    assert ws.reload.pricing_visible_to_members?
    post toggle_pricing_workspace_path(ws.slug)
    refute ws.reload.pricing_visible_to_members?
  end

  test "non-site-admin cannot toggle pricing visibility" do
    workspace_admin = User.create!(email_address: "wa-#{SecureRandom.hex(4)}@example.com", role: "user")
    ws = Workspace.create!(name: "No Toggle WS", owner: @owner)
    ws.memberships.create!(user: workspace_admin, role: "admin")
    sign_in_as(workspace_admin)
    post toggle_pricing_workspace_path(ws.slug)
    refute ws.reload.pricing_visible_to_members?
    assert_redirected_to workspaces_path
  end

  test "Workspace#pricing_visible_for? gates by membership when toggle is on" do
    member  = User.create!(email_address: "m-#{SecureRandom.hex(4)}@example.com", role: "user")
    outside = User.create!(email_address: "o-#{SecureRandom.hex(4)}@example.com", role: "user")
    ws = Workspace.create!(name: "Gated WS", owner: @owner, pricing_visible_to_members: true)
    ws.memberships.create!(user: member, role: "editor")

    assert ws.pricing_visible_for?(@owner),         "site admin always sees pricing"
    assert ws.pricing_visible_for?(member),         "members see pricing when toggle is on"
    refute ws.pricing_visible_for?(outside),        "non-members never see pricing"
    refute ws.pricing_visible_for?(nil),            "anonymous never sees pricing"

    ws.update!(pricing_visible_to_members: false)
    refute ws.pricing_visible_for?(member.reload), "members don't see pricing when toggle is off"
    assert ws.pricing_visible_for?(@owner),        "site admin still sees pricing"
  end

  test "social renders the composer with the timezone form" do
    ws = Workspace.create!(name: "Social WS", owner: @owner)
    sign_in_as(@owner)
    get social_workspace_path(ws.slug)
    assert_response :success
    # The composer page shows the timezone select (owners only).
    assert_match %r{name="workspace\[timezone\]"}, response.body
  end
end
