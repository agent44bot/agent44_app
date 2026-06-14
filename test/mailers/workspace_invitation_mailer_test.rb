require "test_helper"

class WorkspaceInvitationMailerTest < ActionMailer::TestCase
  setup do
    @owner = User.create!(email_address: "mailer-owner-#{SecureRandom.hex(4)}@example.com")
    @ws    = Workspace.create!(name: "Finger Lakes Culinary", owner: @owner)
    @inv   = @ws.invitations.create!(invited_by: @owner, email: "newcomer@example.com", role: "editor")
  end

  test "invite email goes to the invitee with a clear subject" do
    mail = WorkspaceInvitationMailer.invite(@inv)
    assert_equal [ "newcomer@example.com" ], mail.to
    assert_match @ws.name, mail.subject
    assert_match "Agent44 Labs", mail.subject
  end

  test "invite email contains the accept link with the invitation token" do
    mail = WorkspaceInvitationMailer.invite(@inv)
    body = mail.body.encoded
    # The recipient must be able to act on it: the tokenized accept/view link.
    assert_match @inv.token, body, "the email must contain the invitation's accept link"
    assert_match "/invitations/#{@inv.token}", body
    assert_match @ws.name, body
  end

  test "invite email is addressed using the invitation's normalized email" do
    inv = @ws.invitations.create!(invited_by: @owner, email: "MixedCase@Example.com", role: "viewer")
    mail = WorkspaceInvitationMailer.invite(inv)
    assert_equal [ "mixedcase@example.com" ], mail.to
  end
end
