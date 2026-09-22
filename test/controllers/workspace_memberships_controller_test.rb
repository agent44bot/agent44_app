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

  test "an admin can change a member's role and is sent back where they came from" do
    admin_user = User.create!(email_address: "adm-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: admin_user, role: "admin")
    sign_in_as admin_user
    patch workspace_membership_path(workspace_slug: @ws.slug, id: @editor.id),
          params: { role: "admin" }, headers: { "HTTP_REFERER" => "http://www.example.com/nykitchen" }
    assert_equal "admin", @editor.reload.role
    assert_redirected_to "http://www.example.com/nykitchen"
  end

  test "managers see a role picker for non-owner members, editors see labels" do
    picker = "form[action='#{workspace_membership_path(workspace_slug: @ws.slug, id: @editor.id)}'] select[name=role]"
    sign_in_as @owner
    get workspace_path(@ws.slug)
    assert_select picker, count: 1

    sign_in_as @editor_user
    get workspace_path(@ws.slug)
    assert_select picker, count: 0
  end

  test "the owner can demote a member to viewer" do
    sign_in_as @owner
    patch workspace_membership_path(workspace_slug: @ws.slug, id: @editor.id), params: { role: "viewer" }
    assert_equal "viewer", @editor.reload.role
  end

  test "a non-admin member cannot change roles" do
    other = User.create!(email_address: "ed2-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: other, role: "editor")
    sign_in_as other
    patch workspace_membership_path(workspace_slug: @ws.slug, id: @editor.id), params: { role: "admin" }
    assert_equal "editor", @editor.reload.role
  end

  test "nobody can be made owner and the owner's role cannot change" do
    sign_in_as @owner
    patch workspace_membership_path(workspace_slug: @ws.slug, id: @editor.id), params: { role: "owner" }
    assert_equal "editor", @editor.reload.role

    owner_membership = @ws.memberships.find_by(user_id: @owner.id)
    patch workspace_membership_path(workspace_slug: @ws.slug, id: owner_membership.id), params: { role: "editor" }
    assert_equal "owner", owner_membership.reload.role
  end

  test "an admin cannot demote themselves" do
    admin_user = User.create!(email_address: "adm-#{SecureRandom.hex(4)}@example.com")
    mine = @ws.memberships.create!(user: admin_user, role: "admin")
    sign_in_as admin_user
    patch workspace_membership_path(workspace_slug: @ws.slug, id: mine.id), params: { role: "editor" }
    assert_equal "admin", mine.reload.role
  end
end
