class NykFilterCardCheckJob < ApplicationJob
  queue_as :default

  THRESHOLD_DAYS = 14

  def perform
    return if Setting.time("nyk.filter_card_hidden_at")

    shipped = Setting.time("nyk.filter_card_shipped_at")
    unless shipped
      Setting.touch_time("nyk.filter_card_shipped_at")
      return
    end

    return if shipped > THRESHOLD_DAYS.days.ago

    last_expand = Setting.time("nyk.filter_card_last_expanded_at")
    return if last_expand && last_expand >= THRESHOLD_DAYS.days.ago

    Setting.touch_time("nyk.filter_card_hidden_at")

    Notification.notify!(
      level: "info",
      source: "nyk_ui",
      title: "NYK Filter card auto-hidden",
      body: "Nobody expanded the Filter card on /nykitchen for #{THRESHOLD_DAYS} days, so it's now hidden. Re-enable by deleting the `nyk.filter_card_hidden_at` setting via `Setting.delete_key('nyk.filter_card_hidden_at')`.",
      telegram: true
    )
  end
end
