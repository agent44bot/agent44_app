class WorkspaceInvitationsController < ApplicationController
  before_action :load_workspace,  only: [ :create, :destroy ]
  before_action :require_member,  only: :create
  before_action :require_admin,   only: :destroy

  # Rank used to cap what role an inviter may grant. Everyone in a workspace can
  # invite, but never at a role above their own (a viewer can't mint an admin).
  ROLE_RANK = { "viewer" => 1, "editor" => 2, "admin" => 3, "owner" => 4 }.freeze

  def create
    invitation = @workspace.invitations.new(
      invited_by: current_user,
      email:      params[:email].to_s,
      role:       capped_invite_role(params[:role])
    )
    if invitation.save
      WorkspaceInvitationMailer.invite(invitation).deliver_later
      redirect_to social_workspace_path(@workspace.slug),
                  notice: "Invite sent to #{invitation.email}."
    else
      redirect_to social_workspace_path(@workspace.slug),
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
    redirect_to social_workspace_path(invitation.workspace.slug), notice: "Joined #{invitation.workspace.name}."
  rescue ActiveRecord::RecordNotFound
    redirect_to workspaces_path, alert: "Invitation not found."
  rescue WorkspaceInvitation::EmailMismatch
    redirect_to workspace_invitation_view_path(token: invitation.token),
                alert: "This invitation was sent to #{invitation.email}. Sign out and sign in with that email to accept."
  rescue => e
    redirect_to workspaces_path, alert: "Could not accept: #{e.message}"
  end

  def destroy
    invitation = @workspace.invitations.find(params[:id])
    invitation.revoke!
    redirect_to social_workspace_path(@workspace.slug), notice: "Invite revoked."
  end

  private

  def load_workspace
    @workspace = Workspace.find_by!(slug: params[:workspace_slug])
  end

  def require_admin
    membership = @workspace.memberships.find_by(user_id: current_user.id)
    return if membership&.admin?
    redirect_to social_workspace_path(@workspace.slug), alert: "Only workspace admins can manage invites."
  end

  # Any member (or a site admin) can send invites.
  def require_member
    return if current_user&.admin?
    return if @workspace.member?(current_user)
    redirect_to social_workspace_path(@workspace.slug), alert: "Join the workspace to invite people."
  end

  # Clamp the requested role to what the inviter is allowed to grant: never
  # above their own role. Site admins may grant any (non-owner) role. Falls
  # back to editor when allowed, otherwise the highest role they can grant.
  def capped_invite_role(requested)
    requested = requested.to_s.presence_in(%w[admin editor viewer])
    my_rank   = current_user&.admin? ? 4 : (ROLE_RANK[@workspace.role_for(current_user)] || 0)
    allowed   = %w[viewer editor admin].select { |r| ROLE_RANK[r] <= my_rank }
    return requested if requested && allowed.include?(requested)
    allowed.include?("editor") ? "editor" : (allowed.last || "viewer")
  end

  def current_user
    Current.user
  end

  def accept_url(invitation)
    workspace_invitation_accept_url(token: invitation.token)
  end
end
