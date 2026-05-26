module InvitationAutoAccept
  extend ActiveSupport::Concern

  private

  # When a freshly-authenticated user's email matches one or more pending
  # workspace invitations, consume them so they land directly in the
  # workspace instead of revisiting the email link. accept! enforces the
  # email match itself — this is just a convenience. Returns the accepted
  # invitations. Shared by signup (password) and passwordless sign-in.
  def auto_accept_pending_invitations(user)
    return [] if user.email_address.blank?
    WorkspaceInvitation.pending
      .where("LOWER(email) = ?", user.email_address.downcase)
      .each_with_object([]) do |invitation, accepted|
        invitation.accept!(user)
        accepted << invitation
      rescue WorkspaceInvitation::EmailMismatch, ActiveRecord::RecordInvalid
        next
      end
  end
end
