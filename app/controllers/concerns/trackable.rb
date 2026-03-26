module Trackable
  extend ActiveSupport::Concern

  included do
    before_action :track_page_view
  end

  private

  def track_page_view
    return unless request.get?
    return if controller_path.start_with?("admin", "api", "rails")
    return if request.path.match?(/\.(js|css|png|jpg|svg|ico|woff2?)$/)
    return if Current.session&.user&.admin?
    return if bot_request?

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

  BOT_PATTERNS = /
    bot|crawler|spider|scraper|slurp|
    googlebot|bingbot|yandexbot|baiduspider|
    duckduckbot|facebookexternalhit|twitterbot|
    linkedinbot|embedly|quora|pinterest|
    semrushbot|ahrefsbot|mj12bot|dotbot|
    gptbot|chatgpt|anthropic|claude|
    go-http-client|python-requests|curl|wget|
    httpclient|okhttp|java\/|
    applebot|petalbot|bytespider|
    nexus\s5x|mediapartners
  /ix

  def bot_request?
    ua = request.user_agent.to_s
    ua.blank? || ua.match?(BOT_PATTERNS)
  end
end
