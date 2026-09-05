# Resolves which workspace a kitchen request is for.
#
# Slice 1 of the multi-tenant refactor: every kitchen controller reads the
# tenant from here instead of Workspace.find_by(slug: "nykitchen"). The slug
# comes from params[:workspace_slug] (set by the route) and falls back to NY
# Kitchen, whose /nykitchen/* URLs are permanent (QR codes, the display
# screen, iOS deep links). Slice 2 mounts the same routes under any
# kitchen-enabled slug, at which point the fallback only serves /nykitchen.
module KitchenTenant
  extend ActiveSupport::Concern

  included do
    helper_method :current_workspace, :nyk_workspace if respond_to?(:helper_method)
  end

  private

  # The kitchen workspace for this request. 404s when the slug names no
  # kitchen-enabled workspace so a typo can't fall through to NYK's data.
  def current_workspace
    return @current_workspace if defined?(@current_workspace)

    slug = params[:workspace_slug].presence || Workspace::NYK_SLUG
    @current_workspace =
      if slug == Workspace::NYK_SLUG
        # NY Kitchen's /nykitchen/* URLs are permanent (QR codes, the display
        # screen, iOS deep links): never gated on kitchen_enabled, so a flag
        # slip can't take the display down.
        Workspace.find_by(slug: slug)
      else
        Workspace.kitchen.find_by(slug: slug)
      end
    raise ActiveRecord::RecordNotFound, "no kitchen workspace for #{slug}" unless @current_workspace
    @current_workspace
  end

  # Legacy name used throughout the kitchen views and helpers. Same object.
  alias_method :nyk_workspace, :current_workspace

  def require_workspace_manager
    head :not_found unless current_workspace.manager?(Current.user)
  end

  # Non-public kitchen pages are for the workspace's members, site admins,
  # and the App Store reviewer account. Anyone else signed in gets a 404
  # (not a redirect, so the page's existence is not confirmed). Replaces the
  # old rule where any signed-in user could read every /nykitchen page.
  def require_kitchen_access
    head :not_found unless kitchen_access?(Current.user)
  end

  def kitchen_access?(user)
    return false unless user
    user.admin? || user.reviewer? || current_workspace.member?(user)
  end
end
