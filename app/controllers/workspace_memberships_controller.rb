class WorkspaceMembershipsController < ApplicationController
  before_action :load_workspace, only: [ :update, :destroy ]
  before_action :require_admin,  only: [ :update, :destroy ]

  EDITABLE_ROLES = %w[admin editor viewer].freeze

  # Owner/admin changes a member's role. The owner's role is fixed, nobody is
  # made owner here, and an admin can't demote themselves out of admin.
  # Redirects back to wherever the list was shown (/nykitchen or the hub).
  def update
    membership = @workspace.memberships.find(params[:id])
    role = params[:role].to_s
    fallback = social_workspace_path(@workspace.slug)

    if membership.owner?
      redirect_back_or_to fallback, alert: "You can't change the workspace owner's role." and return
    end
    unless EDITABLE_ROLES.include?(role)
      redirect_back_or_to fallback, alert: "Pick admin, editor, or viewer." and return
    end
    if membership.user_id == current_user.id && role != "admin"
      redirect_back_or_to fallback, alert: "You can't remove your own admin access." and return
    end

    membership.update!(role: role)
    name = membership.user.email_address.presence || membership.user.display_identifier
    redirect_back_or_to fallback, notice: "#{name} is now #{role == "admin" ? "an" : "a"} #{role}."
  end

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
    redirect_to social_workspace_path(@workspace.slug), alert: "Only workspace admins can manage members."
  end

  def current_user
    Current.user
  end
end
