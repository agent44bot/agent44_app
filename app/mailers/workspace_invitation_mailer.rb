class WorkspaceInvitationMailer < ApplicationMailer
  def invite(invitation)
    @invitation = invitation
    @workspace  = invitation.workspace
    @inviter    = invitation.invited_by
    @accept_url = workspace_invitation_view_url(token: invitation.token)
    @expires_at = invitation.expires_at

    mail to: invitation.email,
         subject: "#{@inviter.display_identifier} invited you to #{@workspace.name} on Agent44 Labs"
  end
end
