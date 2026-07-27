class NykScrapeDataFreshnessCheckJob < ApplicationJob
  queue_as :default

  # Alerts (email + iOS push + Telegram) when the NY Kitchen availability data
  # goes stale or empty, i.e. the scrape has broken.
  #
  # The scrape (Mac mini primary + laptop stopgap) runs every 3h and POSTs to
  # /api/v1/kitchen_snapshots, which rewrites the day's KitchenSnapshot by
  # destroying and recreating its KitchenEvents each run. So:
  #   * the newest KitchenEvent.created_at is "when availability was last
  #     successfully refreshed," and
  #   * a latest snapshot with zero events means the most recent scrape wiped
  #     availability (the "shows old data" failure mode from PR #443).
  # Either one means the scrape is broken. This watches the actual data, so it
  # catches every cause at once (mini down, laptop stopgap down, node/PATH bug,
  # network, 0-event scrape) rather than one runner's heartbeat.
  #
  # Cadence is 3h, so ~2 missed cycles (7h) with headroom for a slow run = stale.
  MAX_AGE          = 7.hours
  REALERT_COOLDOWN = 12.hours
  STATE_KEY        = "nyk.scrape_data_freshness.last_alert_at"

  # Ops alert: the two NY Kitchen owners (Rich + Lora), not the wider daily
  # digest list. Mirrors KitchenDigestEmailJob::FALLBACK_RECIPIENTS.
  EMAIL_RECIPIENTS = [ "botwhisperer@hey.com", "lora.downie@nykitchen.com" ].freeze

  def perform
    reason = staleness_reason
    return unless reason

    # Debounce: one alert per cooldown window so a persistent outage doesn't
    # ping every hour until it's fixed.
    last_alert = Setting.time(STATE_KEY)
    return if last_alert && last_alert >= REALERT_COOLDOWN.ago

    Setting.touch_time(STATE_KEY)
    alert!(reason)
  end

  private

  # Returns a human-readable reason string if the scrape looks broken, else nil.
  def staleness_reason
    latest = KitchenSnapshot.latest
    return "No KitchenSnapshot rows exist at all: the scrape has never posted." if latest.nil?

    if latest.kitchen_events.count.zero?
      return "The latest snapshot (#{latest.taken_on}) has 0 events. The most recent scrape wiped availability."
    end

    last_at = KitchenEvent.maximum(:created_at)
    return nil if last_at && (Time.current - last_at) <= MAX_AGE

    age_hr = last_at ? ((Time.current - last_at) / 3600.0).round(1) : nil
    when_s = last_at ? last_at.in_time_zone("America/New_York").strftime("%b %-d %-I:%M %p %Z") : "unknown"
    "No fresh scrape in #{age_hr}h (availability last refreshed #{when_s})."
  end

  def alert!(reason)
    title = "NY Kitchen scrape looks broken"
    body  = "#{reason}\n\nThe every-3h NY Kitchen scrape may have stopped " \
            "(Mac mini primary plus laptop stopgap). Check the mini's launchd " \
            "job, the laptop stopgap (com.agent44.nyk-scrape-prod), and " \
            "POST /api/v1/kitchen_snapshots. Tracking: issue #444."

    # One Telegram + one admin-log record (user-less), then a per-user iOS push
    # so each recipient's app icon badge tracks their own unread count. Same
    # shape as the controller's broadcast_kitchen_alert.
    Notification.notify!(level: "error", source: "nyk_scrape", title: title, body: body, telegram: true)

    push_recipients.each do |user|
      Notification.notify!(
        level: "error", source: "nyk_scrape", title: title, body: body,
        apns: true, apns_url: "/nykitchen", apns_user: user, workspace: nyk_workspace
      )
    end

    KitchenMailer.scrape_broken(reason: reason, recipients: EMAIL_RECIPIENTS).deliver_later
  end

  # Admins + NY Kitchen workspace members with an email (today: Rich + Lora),
  # matching KitchenSnapshotsController#kitchen_recipients.
  def push_recipients
    admin_ids  = User.where(role: "admin").pluck(:id)
    member_ids = nyk_workspace&.users&.pluck(:id) || []
    User.where(id: admin_ids + member_ids).where.not(email_address: nil)
  end

  def nyk_workspace
    @nyk_workspace ||= Workspace.find_by(slug: "nykitchen")
  end
end
