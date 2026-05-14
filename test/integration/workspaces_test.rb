require "test_helper"

class WorkspacesTest < ActionDispatch::IntegrationTest
  setup do
    @owner   = User.create!(email_address: "ws-o-#{SecureRandom.hex(4)}@example.com")
    @viewer  = User.create!(email_address: "ws-v-#{SecureRandom.hex(4)}@example.com")
    @outside = User.create!(email_address: "ws-x-#{SecureRandom.hex(4)}@example.com")
  end

  test "GET /workspaces requires sign-in" do
    get workspaces_path
    assert_redirected_to %r{/session/new}
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

  test "POST /workspaces creates one and makes you owner" do
    sign_in_as(@owner)
    assert_difference -> { Workspace.count }, 1 do
      post workspaces_path, params: { workspace: { name: "Brand New", description: "hi", timezone: "Eastern Time (US & Canada)" } }
    end
    ws = Workspace.order(:created_at).last
    assert_redirected_to workspace_path(ws.slug)
    assert_equal "owner", ws.role_for(@owner)
  end

  test "slug auto-dedupes" do
    sign_in_as(@owner)
    post workspaces_path, params: { workspace: { name: "Magenta", timezone: "UTC" } }
    post workspaces_path, params: { workspace: { name: "Magenta", timezone: "UTC" } }
    slugs = Workspace.where(name: "Magenta").pluck(:slug).sort
    assert_equal ["magenta", "magenta-2"], slugs
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
    assert_redirected_to workspace_path(ws.slug)
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

  test "admin (non-owner) can also delete" do
    ws = Workspace.create!(name: "AdminDoomed", owner: @owner)
    admin = User.create!(email_address: "ws-a-#{SecureRandom.hex(4)}@example.com")
    ws.memberships.create!(user: admin, role: "admin")
    sign_in_as(admin)
    delete workspace_path(ws.slug)
    assert_redirected_to workspaces_path
    refute Workspace.exists?(ws.id)
  end

  test "admin can update timezone inline" do
    ws = Workspace.create!(name: "TZWS", owner: @owner, timezone: "UTC")
    sign_in_as(@owner)
    patch workspace_path(ws.slug), params: { workspace: { timezone: "Eastern Time (US & Canada)" } }
    assert_redirected_to workspace_path(ws.slug)
    assert_equal "Eastern Time (US & Canada)", ws.reload.timezone
  end

  test "viewer cannot update timezone" do
    ws = Workspace.create!(name: "TZNo", owner: @owner, timezone: "UTC")
    ws.memberships.create!(user: @viewer, role: "viewer")
    sign_in_as(@viewer)
    patch workspace_path(ws.slug), params: { workspace: { timezone: "Eastern Time (US & Canada)" } }
    assert_equal "UTC", ws.reload.timezone
  end
end
