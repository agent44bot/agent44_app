class WorkspaceMembershipsController < ApplicationController
  before_action :load_workspace, only: [ :destroy ]
  before_action :require_admin,  only: [ :destroy ]

  # Owner/admin removes a member. The owner can't be removed here (transfer or
  # delete the workspace instead).
  def destroy
    membership = @workspace.memberships.find(params[:id])
    if membership.owner?
      redirect_to social_workspace_path(@workspace.slug),
                  alert: "You can't remove the workspace owner." and return
    end
    email = membership.user.email_address.presence || membership.user.display_identifier
    membership.destroy
    redirect_to social_workspace_path(@workspace.slug), notice: "Removed #{email} from the workspace."
  end

  private

  def load_workspace
    @workspace = Workspace.find_by!(slug: params[:workspace_slug])
  end

  def require_admin
    membership = @workspace.memberships.find_by(user_id: current_user.id)
    return if membership&.admin?
    redirect_to social_workspace_path(@workspace.slug), alert: "Only workspace admins can remove members."
  end

  def current_user
    Current.user
  end
end
