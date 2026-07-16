require "test_helper"

class WorkspaceMembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "own-#{SecureRandom.hex(4)}@example.com")
    @ws = Workspace.create!(name: "WS", slug: "rm-#{SecureRandom.hex(4)}", owner: @owner,
                            timezone: "Eastern Time (US & Canada)")
    @editor_user = User.create!(email_address: "ed-#{SecureRandom.hex(4)}@example.com")
    @editor = @ws.memberships.create!(user: @editor_user, role: "editor")
  end

  test "an admin can remove a member" do
    admin_user = User.create!(email_address: "adm-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: admin_user, role: "admin")
    sign_in_as admin_user
    assert_difference -> { @ws.memberships.count }, -1 do
      delete workspace_membership_path(workspace_slug: @ws.slug, id: @editor.id)
    end
    assert_redirected_to social_workspace_path(@ws.slug)
  end

  test "the owner can remove a member" do
    sign_in_as @owner
    assert_difference -> { @ws.memberships.count }, -1 do
      delete workspace_membership_path(workspace_slug: @ws.slug, id: @editor.id)
    end
  end

  test "a non-admin member cannot remove anyone" do
    viewer = User.create!(email_address: "vw-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: viewer, role: "viewer")
    sign_in_as viewer
    assert_no_difference -> { @ws.memberships.count } do
      delete workspace_membership_path(workspace_slug: @ws.slug, id: @editor.id)
    end
  end

  test "the workspace owner membership cannot be removed" do
    sign_in_as @owner
    owner_membership = @ws.memberships.find_by(user_id: @owner.id)
    assert_no_difference -> { @ws.memberships.count } do
      delete workspace_membership_path(workspace_slug: @ws.slug, id: owner_membership.id)
    end
    assert_redirected_to social_workspace_path(@ws.slug)
  end
end
