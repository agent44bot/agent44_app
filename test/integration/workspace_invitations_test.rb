require "test_helper"

class WorkspaceInvitationsIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @owner    = User.create!(email_address: "winv-o-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @editor   = User.create!(email_address: "winv-e-#{SecureRandom.hex(4)}@example.com")
    @teammate = User.create!(email_address: "winv-t-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @ws       = Workspace.create!(name: "Invite WS", owner: @owner)
    @ws.memberships.create!(user: @editor, role: "editor")
  end

  test "admin can create an invitation and an email is queued" do
    sign_in_as(@owner)
    assert_enqueued_emails(1) do
      assert_difference -> { WorkspaceInvitation.count }, 1 do
        post workspace_invitations_path(workspace_slug: @ws.slug),
             params: { email: "new@example.com", role: "editor" }
      end
    end
    assert_redirected_to social_workspace_path(@ws.slug)
    assert_match /Invite sent to new@example.com/, flash[:notice]
  end

  test "editor (non-admin) cannot create an invitation" do
    sign_in_as(@editor)
    assert_no_difference -> { WorkspaceInvitation.count } do
      post workspace_invitations_path(workspace_slug: @ws.slug),
           params: { email: "blocked@example.com", role: "editor" }
    end
  end

  test "accept link adds the signed-in user as a member" do
    inv = @ws.invitations.create!(invited_by: @owner, email: @teammate.email_address, role: "editor")
    sign_in_as(@teammate)
    get workspace_invitation_view_path(token: inv.token)
    assert_response :success
    assert_match @ws.name, response.body

    assert_difference -> { @ws.memberships.count }, 1 do
      post workspace_invitation_accept_path(token: inv.token)
    end
    assert_redirected_to social_workspace_path(@ws.slug)
    assert_equal "editor", @ws.role_for(@teammate)
  end

  test "expired invitation is rejected at view time" do
    inv = @ws.invitations.create!(invited_by: @owner, email: @teammate.email_address, role: "editor")
    inv.update_columns(expires_at: 1.hour.ago)
    sign_in_as(@teammate)
    get workspace_invitation_view_path(token: inv.token)
    assert_redirected_to workspaces_path
    assert_match /no longer valid/, flash[:alert]
  end

  test "revoked invitation is rejected at view time" do
    inv = @ws.invitations.create!(invited_by: @owner, email: @teammate.email_address, role: "editor")
    inv.revoke!
    sign_in_as(@teammate)
    get workspace_invitation_view_path(token: inv.token)
    assert_redirected_to workspaces_path
    assert_match /no longer valid/, flash[:alert]
  end
end
