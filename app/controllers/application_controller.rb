class ApplicationController < ActionController::Base
  include Authentication
  include Trackable
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :enforce_workspace_scope

  helper_method :impersonating?

  private

  # Convenience for views/controllers that need to know if the current
  # session is operating under an admin impersonation.
  def impersonating?
    Current.session&.impersonating? || false
  end

  # Block destructive or identity-changing actions while impersonating, so an
  # admin viewing as Lora can't nuke her account or reset her email by
  # accident. Returns true if the request was blocked.
  def forbid_impersonation!
    return false unless impersonating?
    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, alert: "Blocked while impersonating. Stop impersonating first." }
      format.json { render json: { error: "blocked_while_impersonating" }, status: :forbidden }
    end
    true
  end

  # Paths a non-admin signed-in user can reach. /nykitchen lives here because
  # NYK is still a workspace destination (the agents hub for NY Kitchen);
  # /api/assets/rails are infrastructure paths, never user-facing redirects.
  WORKSPACE_ALLOWED_PREFIXES = %w[/nykitchen /workspaces /invitations /notifications /session /sign_in /email_verification /passwords /settings /impersonate /api /assets /rails/active_storage].freeze

  # Non-admin signed-in users are sandboxed to workspace-shaped URLs.
  # Admins see everything (marketing pages, /pulse, /jobs, /admin, etc.).
  # Signed-out users are unaffected — they can hit the marketing home.
  def enforce_workspace_scope
    return unless authenticated?
    return if Current.user&.admin?
    path = request.path
    return if WORKSPACE_ALLOWED_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
    redirect_to "/workspaces"
  end
end
