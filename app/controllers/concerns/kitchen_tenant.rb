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

    slug = params[:workspace_slug].presence
    @current_workspace =
      if slug
        Workspace.kitchen.find_by(slug: slug)
      else
        # No slug on the route = NY Kitchen's permanent /nykitchen/* URLs. Not
        # gated on kitchen_enabled so a flag slip can't take the display down.
        Workspace.find_by(slug: Workspace::NYK_SLUG)
      end
    raise ActiveRecord::RecordNotFound, "no kitchen workspace for #{slug || Workspace::NYK_SLUG}" unless @current_workspace
    @current_workspace
  end

  # Legacy name used throughout the kitchen views and helpers. Same object.
  alias_method :nyk_workspace, :current_workspace

  def require_workspace_manager
    head :not_found unless current_workspace.manager?(Current.user)
  end
end
