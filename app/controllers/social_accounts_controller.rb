class SocialAccountsController < ApplicationController
  before_action :load_workspace
  before_action :require_admin

  def destroy
    account = @workspace.social_accounts.find(params[:id])
    label = account.label
    account.destroy
    redirect_to workspace_path(@workspace.slug), notice: "Disconnected #{label}."
  end

  private

  def load_workspace
    @workspace = Workspace.find_by!(slug: params[:workspace_slug])
  end

  def require_admin
    return if @workspace.memberships.find_by(user_id: current_user.id)&.admin?
    redirect_to workspace_path(@workspace.slug), alert: "Only workspace admins can manage accounts."
  end

  def current_user
    Current.session.user
  end
end
