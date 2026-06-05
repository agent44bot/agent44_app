module Trackable
  extend ActiveSupport::Concern

  included do
    before_action :track_page_view
  end

  private

  def track_page_view
    # Track any user-initiated request — GET/POST/PUT/PATCH/DELETE. Skipping
    # OPTIONS (CORS preflights) and HEAD (link prefetches) which aren't
    # meaningful user actions.
    return if %w[OPTIONS HEAD].include?(request.method)
    return if controller_path.start_with?("api", "rails")
    return if request.path.match?(/\.(js|css|png|jpg|svg|ico|woff2?)$/)
    return if bot_request?

    session_id = cookies[:visitor_sid]
    unless session_id.present?
      session_id = SecureRandom.uuid
      cookies[:visitor_sid] = { value: session_id, expires: 30.days.from_now, httponly: true }
    end

    TrackPageViewJob.perform_later(
      path: request.path,
      method: request.method,
      # Fly's edge proxy is what remote_ip sees (the public proxy hop isn't
      # trusted); the real client IP arrives in Fly-Client-IP.
      ip_address: request.headers["Fly-Client-IP"].presence || request.remote_ip,
      user_agent: request.user_agent,
      referrer: request.referrer,
      user_id: Current.user&.id,
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

  # IP-based block list. Empty by default — 66.241.125.168 used to live
  # here flagged as a Google crawler, but that address is actually fly's
  # edge proxy, and Rails surfaces it via request.remote_ip because the
  # public-IP proxy isn't trusted by default. Blocking it silently broke
  # PageView tracking for every real user. UA-based bot filtering below
  # still catches actual crawlers.
  BLOCKED_IPS = Set.new.freeze

  def bot_request?
    return true if BLOCKED_IPS.include?(request.remote_ip)
    ua = request.user_agent.to_s
    ua.blank? || ua.match?(BOT_PATTERNS)
  end
end
