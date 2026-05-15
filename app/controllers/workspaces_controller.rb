class WorkspacesController < ApplicationController
  include FleetSocialAccess
  before_action :load_workspace,  only: [:show, :update, :destroy]
  before_action :require_member,  only: [:show]
  before_action :require_admin,   only: [:update, :destroy]

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

  def update
    if @workspace.update(workspace_params)
      redirect_to workspace_path(@workspace.slug), notice: "Workspace updated."
    else
      redirect_to workspace_path(@workspace.slug), alert: "Update failed: #{@workspace.errors.full_messages.to_sentence}"
    end
  end

  def destroy
    name = @workspace.name
    @workspace.destroy!
    redirect_to workspaces_path, notice: "Deleted workspace #{name}."
  end

  def show
    @memberships  = @workspace.memberships.includes(:user).order(:created_at)
    @invitations  = @workspace.invitations.pending.order(created_at: :desc)
    @social_accounts = @workspace.social_accounts.order(:platform, :handle)
    @posts        = @workspace.workspace_posts.recent.limit(10)
    @my_role      = @workspace.role_for(current_user)
    @writer       = WorkspaceMembership::ROLES.then { %w[owner admin editor].include?(@my_role) }
    @x_account        = @workspace.social_accounts.active.for_platform("x").first
    @bluesky_account  = @workspace.social_accounts.active.for_platform("bluesky").first
    @threads_account  = @workspace.social_accounts.active.for_platform("threads").first
    @facebook_account = @workspace.social_accounts.active.for_platform("facebook").first
    @connected_platforms = [@x_account && "x", @bluesky_account && "bluesky", @threads_account && "threads", @facebook_account && "facebook"].compact
    @drafts           = @workspace.workspace_drafts.unscheduled.recent.limit(10)
    @scheduled_drafts = @workspace.workspace_drafts.scheduled.limit(20)
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

  def require_admin
    return if @workspace.memberships.find_by(user_id: current_user.id)&.admin?
    redirect_to workspace_path(@workspace.slug), alert: "Only workspace admins can do that."
  end

  def current_user
    Current.session.user
  end
end
