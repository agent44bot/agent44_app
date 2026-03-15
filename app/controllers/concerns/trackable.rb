module Trackable
  extend ActiveSupport::Concern

  included do
    before_action :track_page_view
  end

  private

  def track_page_view
    return unless request.get?
    return if Current.session&.user&.admin?
    return if controller_path.start_with?("admin", "api", "rails")
    return if request.path.match?(/\.(js|css|png|jpg|svg|ico|woff2?)$/)

    session_id = cookies[:visitor_sid]
    unless session_id.present?
      session_id = SecureRandom.uuid
      cookies[:visitor_sid] = { value: session_id, expires: 30.days.from_now, httponly: true }
    end

    TrackPageViewJob.perform_later(
      path: request.path,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      referrer: request.referrer,
      user_id: Current.session&.user&.id,
      session_id: session_id
    )
  end
end
