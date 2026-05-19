class ApplicationController < ActionController::Base
  include Authentication
  include Trackable
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :enforce_workspace_scope

  private

  # Paths a non-admin signed-in user can reach. /nykitchen lives here because
  # NYK is still a workspace destination (the agents hub for NY Kitchen);
  # /api/assets/rails are infrastructure paths, never user-facing redirects.
  WORKSPACE_ALLOWED_PREFIXES = %w[/nykitchen /workspaces /invitations /notifications /session /email_verification /passwords /settings /api /assets /rails/active_storage].freeze

  # Non-admin signed-in users are sandboxed to workspace-shaped URLs.
  # Admins see everything (marketing pages, /pulse, /jobs, /admin, etc.).
  # Signed-out users are unaffected — they can hit the marketing home.
  def enforce_workspace_scope
    return unless authenticated?
    return if Current.session&.user&.admin?
    path = request.path
    return if WORKSPACE_ALLOWED_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
    redirect_to "/workspaces"
  end
end
