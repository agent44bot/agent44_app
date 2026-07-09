# Watches the printed-flyer QR -> scan-redirect -> nykitchen.com chain and
# alerts if a customer scanning a flyer would NOT land on the class page where
# tickets are bought. All checks are in-process (no external calls, no false
# alarms from nykitchen.com's SiteGround CAPTCHA):
#
#   1. AASA must still exclude /nykitchen/r/* from iOS Universal Links, or a
#      scan reopens our app instead of the browser (the bug we shipped once).
#   2. Every active class's tracked link must resolve to an https nykitchen.com
#      (or Tock) ticket URL, not agent44labs or a broken/non-web target.
#   3. Heuristic: if recent scans are dominated by the in-app referrer, scans
#      are probably opening the app instead of the browser.
#
# Alerts once per failure episode (and once on recovery) via an iOS push to the
# alert user + a banner flag the hub reads. Idempotent: safe to run on a cron.
class NykQrHealthCheckJob < ApplicationJob
  queue_as :default

  FAILED_AT   = "nyk.qr_health_failed_at".freeze
  MESSAGE     = "nyk.qr_health_msg".freeze
  ALERT_EMAIL = "nyk.qr_alert_email".freeze

  CALENDAR_URL = "https://nykitchen.com/calendar/".freeze
  # Hosts where a customer can actually read about / buy a class ticket.
  TICKET_HOSTS = %w[nykitchen.com exploretock.com].freeze

  # Referrer heuristic: only meaningful once there's a bit of volume.
  HIJACK_MIN_SCANS = 8
  HIJACK_FRACTION  = 0.6

  def perform
    problems = []
    problems << universal_link_problem
    problems.concat(target_problems)
    problems << hijack_referrer_problem
    problems.compact!

    problems.any? ? raise_alert(problems) : clear_alert
  end

  private

  # 1. AASA still excludes the flyer redirect from Universal Links.
  def universal_link_problem
    paths = WellKnownController::APP_LINK_PATHS
    not_i = paths.index("NOT /nykitchen/r/*")
    all_i = paths.index("/nykitchen/*")
    return nil if not_i && (all_i.nil? || not_i < all_i)
    "Universal Links no longer exclude /nykitchen/r/*: iOS will reopen flyer scans in the agent44labs app instead of sending them to nykitchen.com."
  end

  # 2. Every active tracked link points at a real ticket page.
  def target_problems
    bad = active_tracked_links.reject { |l| ticket_target?(l.url) }
    return [] if bad.empty?
    [ "#{bad.size} QR code(s) resolve somewhere other than a nykitchen.com ticket page (e.g. #{bad.first.url.inspect})." ]
  end

  # 3. Recent scans carrying our own host as referrer suggest the app (or the
  #    on-screen print page), not a clean printed-flyer camera scan.
  def hijack_referrer_problem
    recent = LinkScan.since(24.hours.ago)
    total = recent.count
    return nil if total < HIJACK_MIN_SCANS
    in_app = recent.where("referrer LIKE ?", "%agent44labs.com%").count
    return nil if in_app.to_f / total < HIJACK_FRACTION
    "#{in_app} of #{total} scans in the last 24h carry the in-app referrer: flyer scans may be opening the app instead of nykitchen.com."
  end

  # Tracked links for the currently-advertised classes, plus the footer
  # "all classes" calendar link. Keyed by URL (a snapshot regenerates the
  # KitchenEvent rows, but the tracked link is stable).
  def active_tracked_links
    snap = KitchenSnapshot.latest
    urls = snap ? snap.kitchen_events.upcoming.pluck(:url) : []
    urls << CALENDAR_URL
    TrackedLink.where(url: urls.compact.uniq)
  end

  def ticket_target?(url)
    uri = URI.parse(url.to_s)
    return false unless uri.scheme&.downcase == "https"
    host = uri.host.to_s.downcase
    TICKET_HOSTS.any? { |h| host == h || host.end_with?(".#{h}") }
  rescue URI::InvalidURIError
    false
  end

  def raise_alert(problems)
    body = problems.join(" ")
    already_failing = Setting.time(FAILED_AT).present?
    Setting.touch_time(FAILED_AT)
    Setting.set(MESSAGE, body)
    return if already_failing # push once per episode; the banner stays up meanwhile

    Notification.notify!(
      level: "error",
      source: "nyk_qr",
      title: "NYK flyer QR codes may not reach nykitchen.com",
      body: body,
      apns: true,
      apns_user: alert_user,
      apns_url: "/nykitchen"
    )
  end

  def clear_alert
    return unless Setting.time(FAILED_AT).present?
    Setting.delete_key(FAILED_AT)
    Setting.delete_key(MESSAGE)
    Notification.notify!(
      level: "success",
      source: "nyk_qr",
      title: "NYK flyer QR codes healthy again",
      body: "Flyer scans are resolving to nykitchen.com ticket pages.",
      apns: true,
      apns_user: alert_user,
      apns_url: "/nykitchen"
    )
  end

  def alert_user
    email = Setting.get(ALERT_EMAIL).to_s.strip
    (email.present? && User.find_by(email_address: email)) ||
      Workspace.find_by(slug: "nykitchen")&.owner ||
      User.where(role: "admin").order(:id).first
  end
end
