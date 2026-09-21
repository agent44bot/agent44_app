# Pushes Rich a heads-up the day our Anthropic spend crosses a dollar
# threshold, so a runaway loop or an unusually heavy day is noticed while it
# is happening rather than on the next invoice. (Rich, 2026-09-21, after a
# recipe-import day pushed the key's usage well above its baseline.)
#
# Reads the same AiCallLog rows the billing page does, so the number in the
# push is the number on the page. Hourly, and it alerts at most once a day:
# the point is "today is expensive", which does not need saying twice.
class AiSpendAlertJob < ApplicationJob
  queue_as :default

  THRESHOLD_KEY = "ai_spend.daily_alert_dollars".freeze
  ALERT_EMAIL   = "ai_spend.alert_email".freeze
  ALERTED_ON    = "ai_spend.alerted_on".freeze

  DEFAULT_THRESHOLD = 1.0
  # Named in the push so it is obvious where the money went without opening
  # anything; the rest are summed into "other".
  TOP_SOURCES = 3

  def perform
    today = Date.current # app TZ is Eastern, so "today" is the day Rich is in
    return if Setting.get(ALERTED_ON) == today.to_s

    logs = AiCallLog.where(created_at: today.all_day).to_a
    spend = logs.sum(&:cost_dollars)
    return if spend < threshold

    Setting.set(ALERTED_ON, today.to_s)
    Notification.notify!(
      level: "warning",
      source: "ai_spend",
      title: "Anthropic spend today is #{money(spend)}",
      body: body_for(logs, spend),
      apns: true,
      apns_user: alert_user,
      apns_url: "/nykitchen/billing"
    )
  end

  private

  def threshold
    raw = Setting.get(THRESHOLD_KEY).to_s.strip
    value = raw.to_f
    value.positive? ? value : DEFAULT_THRESHOLD
  end

  # "Over $1.00 on 68 calls. nyk_recipe_extract $1.32, nyk_social_scout $0.09,
  #  2 others $0.04."
  def body_for(logs, spend)
    by_source = logs.group_by(&:source)
                    .transform_values { |ls| ls.sum(&:cost_dollars) }
                    .sort_by { |_s, d| -d }
    named, rest = by_source.first(TOP_SOURCES), by_source.drop(TOP_SOURCES)
    parts = named.map { |source, dollars| "#{source} #{money(dollars)}" }
    parts << "#{rest.size} others #{money(rest.sum(&:last))}" if rest.any?
    "Over #{money(threshold)} on #{logs.size} calls. #{parts.join(', ')}."
  end

  def money(dollars) = format("$%.2f", dollars)

  def alert_user
    email = Setting.get(ALERT_EMAIL).to_s.strip
    (email.present? && User.find_by(email_address: email)) ||
      User.where(role: "admin").order(:id).first
  end
end
