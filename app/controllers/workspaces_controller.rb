class WorkspacesController < ApplicationController
  before_action :load_workspace,    only: [:show, :social, :update, :destroy, :refresh_metrics, :toggle_pricing]
  before_action :require_member,    only: [:show, :social, :refresh_metrics]
  before_action :require_admin,     only: [:update, :destroy]
  before_action :require_site_admin, only: [:new, :create, :toggle_pricing]
  def index
    @workspaces = current_user.workspaces.active.order(:name)
    @owned_count = current_user.owned_workspaces.active.count

    # Single-workspace members (e.g. Lora @ NY Kitchen) land directly in their
    # workspace instead of seeing a one-row list. Site admins always see the
    # full list; ?force=1 is the escape hatch from the hamburger menu.
    if @workspaces.size == 1 && !current_user.admin? && params[:force].blank?
      redirect_to workspace_path(@workspaces.first.slug) and return
    end
  end

  def new
    @workspace = Workspace.new
  end

  def create
    @workspace = Workspace.new(workspace_params.merge(owner: current_user))
    if @workspace.save
      redirect_to social_workspace_path(@workspace.slug), notice: "Workspace created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @workspace.update(workspace_params)
      redirect_to social_workspace_path(@workspace.slug), notice: "Workspace updated."
    else
      redirect_to social_workspace_path(@workspace.slug), alert: "Update failed: #{@workspace.errors.full_messages.to_sentence}"
    end
  end

  def destroy
    name = @workspace.name
    @workspace.destroy!
    redirect_to workspaces_path, notice: "Deleted workspace #{name}."
  end

  # Site-admin toggle: flips whether workspace members see $ amounts
  # on agent pages. Default off matches the previous admin-only behavior.
  def toggle_pricing
    @workspace.update!(pricing_visible_to_members: !@workspace.pricing_visible_to_members)
    state = @workspace.pricing_visible_to_members? ? "shown to members" : "hidden from members"
    redirect_back fallback_location: workspace_path(@workspace.slug),
                  notice: "Pricing #{state}."
  end

  # Manual one-click refresh for the metrics row under Recent posts.
  # Bypasses the recurring job's MIN_REFRESH_INTERVAL gate so users get
  # fresh numbers immediately instead of waiting for the next :23.
  def refresh_metrics
    count = RefreshSocialMetricsJob.new.perform(workspace_id: @workspace.id, force: true)
    redirect_to social_workspace_path(@workspace.slug), notice: "Refreshed metrics on #{count} #{'post'.pluralize(count)}."
  end

  # Workspace agents hub. Today every workspace has just one agent (Social),
  # but the hub gives a consistent shape so future agents (analytics, alerts,
  # etc.) can join the fleet here. NY Kitchen has a richer 4-agent hub at
  # /nykitchen — redirect there so there's one canonical NYK destination.
  def show
    return redirect_to(nykitchen_path, status: 301) if @workspace.slug == "nykitchen"

    @my_role  = @workspace.role_for(current_user)
    @writer   = %w[owner admin editor].include?(@my_role)
    @platforms_connected = @workspace.social_accounts.active.pluck(:platform).map(&:capitalize).uniq.sort
    @posts_total         = @workspace.workspace_posts.count
    @last_post_at        = @workspace.workspace_posts.maximum(:posted_at) || @workspace.workspace_posts.maximum(:created_at)

    # Team management lives on the workspace hub now (was on /social).
    @memberships     = @workspace.memberships.includes(:user).order(:created_at)
    @invitations     = @workspace.invitations.pending.order(created_at: :desc)
    @social_accounts = @workspace.social_accounts.order(:platform, :handle)
  end

  def social
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
    redirect_to social_workspace_path(@workspace.slug), alert: "Only workspace admins can do that."
  end

  def require_site_admin
    return if current_user&.admin?
    redirect_to workspaces_path, alert: "Only site admins can create new workspaces during the dogfood phase."
  end

  def current_user
    Current.user
  end
end
