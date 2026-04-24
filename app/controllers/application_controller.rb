class ApplicationController < ActionController::Base
  include Authentication
  include Trackable
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :enforce_kitchen_only_scope

  private

  KITCHEN_ALLOWED_PREFIXES = %w[/nykitchen /session /email_verification /passwords /settings /api /assets /rails/active_storage].freeze

  def enforce_kitchen_only_scope
    return unless authenticated?
    return unless Current.session&.user&.kitchen_only?
    path = request.path
    return if KITCHEN_ALLOWED_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
    redirect_to "/nykitchen"
  end
end
