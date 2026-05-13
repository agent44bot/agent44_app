class WorkspacesController < ApplicationController
  before_action :load_workspace, only: [:show]
  before_action :require_member, only: [:show]

  def index
    @workspaces = current_user.workspaces.active.order(:name)
    @owned_count = current_user.owned_workspaces.active.count
  end

  def new
    @workspace = Workspace.new
  end

  def create
    @workspace = Workspace.new(workspace_params.merge(owner: current_user))
    if @workspace.save
      redirect_to workspace_path(@workspace.slug), notice: "Workspace created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @memberships  = @workspace.memberships.includes(:user).order(:created_at)
    @invitations  = @workspace.invitations.pending.order(created_at: :desc)
    @social_accounts = @workspace.social_accounts.order(:platform, :handle)
    @posts        = @workspace.workspace_posts.recent.limit(10)
    @my_role      = @workspace.role_for(current_user)
    @writer       = WorkspaceMembership::ROLES.then { %w[owner admin editor].include?(@my_role) }
    @x_account    = @workspace.social_accounts.active.for_platform("x").first
  end

  private

  def workspace_params
    params.require(:workspace).permit(:name, :description, :timezone)
  end

  def load_workspace
    @workspace = Workspace.find_by!(slug: params[:slug])
  end

  def require_member
    return if @workspace.member?(current_user)
    redirect_to workspaces_path, alert: "You're not a member of that workspace."
  end

  def current_user
    Current.session.user
  end
end
