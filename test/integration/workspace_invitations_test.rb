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

  test "editor can create an invitation (capped to editor)" do
    sign_in_as(@editor)
    assert_difference -> { WorkspaceInvitation.count }, 1 do
      post workspace_invitations_path(workspace_slug: @ws.slug),
           params: { email: "byeditor@example.com", role: "editor" }
    end
    assert_equal "editor", WorkspaceInvitation.find_by(email: "byeditor@example.com").role
  end

  test "editor cannot grant a role above their own (admin clamps to editor)" do
    sign_in_as(@editor)
    post workspace_invitations_path(workspace_slug: @ws.slug),
         params: { email: "wannabe-admin@example.com", role: "admin" }
    assert_equal "editor", WorkspaceInvitation.find_by(email: "wannabe-admin@example.com").role
  end

  test "viewer can invite but only at viewer role" do
    viewer = User.create!(email_address: "winv-v-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: viewer, role: "viewer")
    sign_in_as(viewer)
    assert_difference -> { WorkspaceInvitation.count }, 1 do
      post workspace_invitations_path(workspace_slug: @ws.slug),
           params: { email: "byviewer@example.com", role: "admin" }
    end
    assert_equal "viewer", WorkspaceInvitation.find_by(email: "byviewer@example.com").role
  end

  test "a non-member cannot invite" do
    outsider = User.create!(email_address: "winv-out-#{SecureRandom.hex(4)}@example.com")
    sign_in_as(outsider)
    assert_no_difference -> { WorkspaceInvitation.count } do
      post workspace_invitations_path(workspace_slug: @ws.slug),
           params: { email: "nope@example.com", role: "editor" }
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

  test "signup auto-accepts pending invitations matching the new user's email" do
    invitee_email = "auto-#{SecureRandom.hex(4)}@example.com"
    @ws.invitations.create!(invited_by: @owner, email: invitee_email, role: "editor")

    assert_difference -> { User.where(email_address: invitee_email).count }, 1 do
      assert_difference -> { @ws.memberships.count }, 1 do
        post registration_path, params: { user: {
          email_address: invitee_email,
          password: "AutoAccept2026!",
          password_confirmation: "AutoAccept2026!"
        } }
      end
    end
    new_user = User.find_by!(email_address: invitee_email)
    assert_redirected_to workspace_path(@ws.slug)
    assert_match /You've joined/, flash[:notice]
    assert_equal "editor", @ws.role_for(new_user)
  end

  test "signup does not auto-accept invitations addressed to a different email" do
    @ws.invitations.create!(invited_by: @owner, email: "someoneelse@example.com", role: "editor")
    bystander_email = "bystander-#{SecureRandom.hex(4)}@example.com"

    assert_no_difference -> { @ws.memberships.count } do
      post registration_path, params: { user: {
        email_address: bystander_email,
        password: "Bystander2026!",
        password_confirmation: "Bystander2026!"
      } }
    end
    refute_match /You've joined/, flash[:notice].to_s
  end

  test "POST accept refuses a signed-in user whose email doesn't match" do
    bystander = User.create!(email_address: "winv-by-#{SecureRandom.hex(4)}@example.com")
    inv = @ws.invitations.create!(invited_by: @owner, email: "intended@example.com", role: "editor")
    sign_in_as(bystander)
    assert_no_difference -> { @ws.memberships.count } do
      post workspace_invitation_accept_path(token: inv.token)
    end
    assert_redirected_to workspace_invitation_view_path(token: inv.token)
    assert_match /sent to intended@example.com/, flash[:alert]
    assert_nil inv.reload.accepted_at
  end

  test "GET show hides the Accept button on email mismatch" do
    bystander = User.create!(email_address: "winv-bv-#{SecureRandom.hex(4)}@example.com")
    inv = @ws.invitations.create!(invited_by: @owner, email: "someone-else@example.com", role: "editor")
    sign_in_as(bystander)
    get workspace_invitation_view_path(token: inv.token)
    assert_response :success
    # Button text appears in <title> too — assert specifically on the button form action.
    refute_match %r{action="/invitations/[^"]+/accept"}, response.body, "Accept button must be hidden when emails mismatch"
    assert_match %r{someone-else@example.com}, response.body
    assert_match %r{Sign out}, response.body
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

  test "passwordless sign-in auto-accepts a matching pending invitation" do
    # The primary auth path (email code). A brand-new person who was invited
    # should land directly in the workspace on first sign-in.
    invitee_email = "pwless-#{SecureRandom.hex(4)}@example.com"
    @ws.invitations.create!(invited_by: @owner, email: invitee_email, role: "viewer")

    _record, plaintext = LoginCode.issue!(email_address: invitee_email, ip_address: "127.0.0.1")
    assert_difference -> { @ws.memberships.count }, 1 do
      post verify_sign_in_path, params: { email_address: invitee_email, code: plaintext }
    end
    new_user = User.find_by!(email_address: invitee_email)
    assert_equal "viewer", @ws.role_for(new_user)
    assert_redirected_to workspace_path(@ws.slug)
    assert_match /You've joined/, flash[:notice]
  end

  test "admin can revoke a pending invitation" do
    inv = @ws.invitations.create!(invited_by: @owner, email: "revoke-me@example.com", role: "editor")
    sign_in_as(@owner)
    delete workspace_invitation_path(workspace_slug: @ws.slug, id: inv.id)
    assert inv.reload.revoked?
    refute inv.pending?
    assert_match /revoked/i, flash[:notice]
  end

  test "creating an invitation with an invalid email is rejected" do
    sign_in_as(@owner)
    assert_no_enqueued_emails do
      assert_no_difference -> { WorkspaceInvitation.count } do
        post workspace_invitations_path(workspace_slug: @ws.slug),
             params: { email: "not-an-email", role: "editor" }
      end
    end
    assert_match /Couldn't invite/, flash[:alert]
  end
end
