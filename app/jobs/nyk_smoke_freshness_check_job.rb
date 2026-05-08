class NykSmokeFreshnessCheckJob < ApplicationJob
  queue_as :default

  THRESHOLDS = {
    nav: {
      scope:     :nyk_nav,
      label:     "nav (hourly)",
      max_age:   2.hours,
      state_key: "nyk.smoke_freshness.nav.last_alert_at"
    },
    scrape: {
      scope:     :nyk_scrape,
      label:     "scrape (every 3h)",
      max_age:   4.hours,
      state_key: "nyk.smoke_freshness.scrape.last_alert_at"
    }
  }.freeze

  REALERT_COOLDOWN = 6.hours

  def perform
    THRESHOLDS.each { |kind, cfg| check_one(kind, cfg) }
  end

  private

  def check_one(kind, cfg)
    latest = SmokeTestRun.public_send(cfg[:scope]).order(started_at: :desc).first
    return unless latest

    age = Time.current - latest.started_at
    return if age <= cfg[:max_age]

    last_alert = Setting.time(cfg[:state_key])
    return if last_alert && last_alert >= REALERT_COOLDOWN.ago

    Setting.touch_time(cfg[:state_key])
    notify!(kind, cfg, latest, age)
  end

  def notify!(kind, cfg, latest, age)
    age_hr  = (age / 3600.0).round(1)
    last_at = latest.started_at.in_time_zone("America/New_York").strftime("%b %-d %-I:%M %p %Z")

    Notification.notify!(
      level:    "warning",
      source:   "nyk_smoke",
      title:    "NYK smoke #{kind} runs are stale",
      body:     "Latest #{cfg[:label]} run was #{age_hr}h ago at #{last_at}. Expected within #{cfg[:max_age].inspect.gsub(' ', '')}. Possible causes: Mac mini launchd cron stopped firing, GH Actions workflow_dispatch failing fast, or POST /api/v1/smoke_runs broken. Check: gh run list --workflow smoke-nyk.yml --limit 5",
      telegram: true
    )
  end
end
