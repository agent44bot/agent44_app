class WorkspaceInvitationsController < ApplicationController
  include FleetSocialAccess
  before_action :load_workspace,  only: [:create, :destroy]
  before_action :require_admin,   only: [:create, :destroy]

  def create
    invitation = @workspace.invitations.new(
      invited_by: current_user,
      email:      params[:email].to_s,
      role:       params[:role].presence_in(%w[admin editor viewer]) || "editor"
    )
    if invitation.save
      redirect_to workspace_path(@workspace.slug),
                  notice: "Invite created. Share link: #{accept_url(invitation)}"
    else
      redirect_to workspace_path(@workspace.slug),
                  alert: "Couldn't invite: #{invitation.errors.full_messages.to_sentence}"
    end
  end

  def show
    invitation = WorkspaceInvitation.find_by(token: params[:token])
    return redirect_to workspaces_path, alert: "Invitation not found." unless invitation
    return redirect_to workspaces_path, alert: "Invitation no longer valid." unless invitation.pending?
    @invitation = invitation
  end

  def accept
    invitation = WorkspaceInvitation.find_by!(token: params[:token])
    invitation.accept!(current_user)
    redirect_to workspace_path(invitation.workspace.slug), notice: "Joined #{invitation.workspace.name}."
  rescue ActiveRecord::RecordNotFound
    redirect_to workspaces_path, alert: "Invitation not found."
  rescue => e
    redirect_to workspaces_path, alert: "Could not accept: #{e.message}"
  end

  def destroy
    invitation = @workspace.invitations.find(params[:id])
    invitation.revoke!
    redirect_to workspace_path(@workspace.slug), notice: "Invite revoked."
  end

  private

  def load_workspace
    @workspace = Workspace.find_by!(slug: params[:workspace_slug])
  end

  def require_admin
    membership = @workspace.memberships.find_by(user_id: current_user.id)
    return if membership&.admin?
    redirect_to workspace_path(@workspace.slug), alert: "Only workspace admins can manage invites."
  end

  def current_user
    Current.session.user
  end

  def accept_url(invitation)
    workspace_invitation_accept_url(token: invitation.token)
  end
end
