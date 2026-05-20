require "test_helper"

# DELETE /admin/users/:id — admin-only user deletion that cascades the
# user's workspace graph (memberships, owned workspaces, sent invites,
# authored posts/drafts). Mirrors the safety rails on impersonation:
# admins can't be deleted from the UI, you can't delete yourself, and
# the action is blocked while impersonating.
class AdminUsersTest < ActionDispatch::IntegrationTest
  setup do
    @admin       = User.create!(email_address: "adm-#{SecureRandom.hex(4)}@example.com",  role: "admin")
    @other_admin = User.create!(email_address: "adm2-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @target      = User.create!(email_address: "tgt-#{SecureRandom.hex(4)}@example.com",  role: "user", display_name: "Target")
  end

  test "admin can delete a non-admin user and cascade their workspace graph" do
    ws = Workspace.create!(name: "Delete-cascade-#{SecureRandom.hex(2)}", owner: @admin)
    ws.memberships.create!(user: @target, role: "editor")
    ws.invitations.create!(invited_by: @target, email: "future-teammate@example.com", role: "editor")

    sign_in_as(@admin)
    assert_difference -> { User.where(id: @target.id).count }, -1 do
      assert_difference -> { WorkspaceMembership.where(user_id: @target.id).count }, -1 do
        assert_difference -> { WorkspaceInvitation.where(invited_by_id: @target.id).count }, -1 do
          delete admin_user_path(@target)
        end
      end
    end
    assert_redirected_to admin_users_path
    assert_match /Deleted/, flash[:notice]
  end

  test "deleting an owner destroys their workspaces too" do
    owner = User.create!(email_address: "own-#{SecureRandom.hex(4)}@example.com", role: "user")
    ws = Workspace.create!(name: "Owned-#{SecureRandom.hex(2)}", owner: owner)
    sign_in_as(@admin)
    assert_difference -> { Workspace.where(id: ws.id).count }, -1 do
      delete admin_user_path(owner)
    end
  end

  test "refuses to delete an admin user" do
    sign_in_as(@admin)
    assert_no_difference -> { User.where(id: @other_admin.id).count } do
      delete admin_user_path(@other_admin)
    end
    assert_redirected_to admin_users_path
    assert_match /Refusing to delete an admin/, flash[:alert]
  end

  test "admin cannot delete themselves" do
    sign_in_as(@admin)
    assert_no_difference -> { User.where(id: @admin.id).count } do
      delete admin_user_path(@admin)
    end
    assert_redirected_to admin_users_path
    assert_match /can't delete yourself|Refusing/, flash[:alert]
  end

  test "non-admin cannot delete users" do
    bystander = User.create!(email_address: "by-#{SecureRandom.hex(4)}@example.com", role: "user")
    sign_in_as(bystander)
    assert_no_difference -> { User.where(id: @target.id).count } do
      delete admin_user_path(@target)
    end
    assert_match %r{/workspaces|/}, response.location, "non-admin was redirected away from the admin route"
  end

  test "delete is blocked while impersonating" do
    sign_in_as(@admin)
    post impersonate_path(user_id: @target.id)
    assert Current.session.reload.impersonating?
    other_target = User.create!(email_address: "ot-#{SecureRandom.hex(4)}@example.com", role: "user")
    assert_no_difference -> { User.where(id: other_target.id).count } do
      delete admin_user_path(other_target)
    end
  end
end
