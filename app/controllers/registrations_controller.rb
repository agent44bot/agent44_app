class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 1.hour, only: :create, with: -> { redirect_to new_registration_path, alert: "Too many sign-up attempts. Try again later." }

  def new
  end

  def create
    @user = User.new(registration_params)
    if @user.save
      UserMailer.email_verification(@user).deliver_later
      source = session.delete(:soft_gate_source)
      Notification.notify!(
        level: "info",
        source: "signup",
        title: "New user signed up",
        body: "#{@user.email_address}#{source.present? ? " (via #{source})" : ""}"
      )
      start_new_session_for @user
      auto_accepted = auto_accept_pending_invitations(@user)
      destination =
        if auto_accepted.any?
          workspace_path(auto_accepted.first.workspace.slug)
        else
          session.delete(:return_to_after_authenticating) || root_path
        end
      notice = if auto_accepted.any?
        "Welcome! You've joined #{auto_accepted.map { |i| i.workspace.name }.uniq.to_sentence}."
      else
        "Welcome! Check your email to verify your account."
      end
      redirect_to destination, notice: notice
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:display_name, :email_address, :password, :password_confirmation)
  end

  # When a new user's email matches one or more pending invitations,
  # consume them on signup so they land directly in the workspace
  # instead of needing to revisit the email link and click Accept.
  # accept! enforces the email match itself — this is just a convenience.
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
