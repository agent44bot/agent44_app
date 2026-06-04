# Carson's proactive nudges: at most a couple of lock-screen pushes a day,
# each based on a REAL observation (slow sales, no flyers printed, a class
# almost sold out) with a deep link into the right agent view.
#
# Runs hourly via config/recurring.yml; most runs send nothing. A send
# requires, in order:
#   - at least one enabled recipient (Setting "carson_nudges:user_ids",
#     comma-separated user ids — starts as just Rich, flip to add Lora)
#   - inside the 9am-7pm ET window, under the daily budget, and a dice roll
#     (so timing feels random rather than on-the-hour)
#   - a trigger that is actually firing and off cooldown
#
# Manual test from prod console: CarsonNudgeJob.perform_now(force: true)
class CarsonNudgeJob < ApplicationJob
  queue_as :default

  WINDOW_HOURS = (9..19)  # ET, matches config.time_zone
  DAILY_BUDGET = 2
  SEND_CHANCE  = 0.35     # per eligible hourly run -> roughly 1-2 sends/day

  def perform(force: false)
    users = enabled_users
    return if users.empty?
    return unless force || sendable_now?

    nudge = first_triggered_nudge
    return unless nudge

    users.each do |user|
      Notification.notify!(
        level: :info, source: "carson",
        title: nudge[:title], body: nudge[:body],
        apns: true, apns_user: user,
        apns_url: nudge[:url], apns_subtitle: "Carson · Concierge"
      )
    end
    Setting.increment(sent_today_key)
    Setting.touch_time("carson_nudges:cooldown:#{nudge[:key]}")
  end

  private

  def enabled_users
    ids = Setting.get("carson_nudges:user_ids").to_s.split(",").map(&:strip).reject(&:blank?)
    ids.empty? ? [] : User.where(id: ids).to_a
  end

  def sendable_now?
    WINDOW_HOURS.cover?(Time.current.hour) &&
      Setting.counter(sent_today_key) < DAILY_BUDGET &&
      dice_roll < SEND_CHANCE
  end

  # Overridable for deterministic tests.
  def dice_roll
    rand
  end

  def sent_today_key
    "carson_nudges:sent:#{Date.current.iso8601}"
  end

  def cooled_down?(key, days)
    last = Setting.time("carson_nudges:cooldown:#{key}")
    last.nil? || last < days.days.ago
  end

  # First trigger that fires wins. Order = priority.
  def first_triggered_nudge
    slow_sales_nudge || no_flyers_nudge || almost_sold_out_nudge
  end

  # --- Trigger 1: sales pace well behind the daily average (after 1pm ET) ---

  def slow_sales_nudge
    return nil unless cooled_down?("slow_sales", 2)
    return nil if Time.current.hour < 13

    snapshot = KitchenSnapshot.latest
    return nil unless snapshot&.taken_on == Date.current

    avg = KitchenSnapshot.tickets_sold_daily_avg
    return nil unless avg&.positive?

    # Same linear 8am-8pm pace model as the hub.
    now = Time.current
    hour_frac = ((now.hour + now.min / 60.0 - 8.0) / 12.0).clamp(0.0, 1.0)
    expected = avg * hour_frac
    return nil unless expected.positive?

    pace_pct = ((snapshot.tickets_sold_today / expected - 1) * 100).round
    return nil if pace_pct > -20

    {
      key: "slow_sales",
      title: pick(
        "Sales are running a little slow today",
        "Quiet day at the box office so far",
      ),
      body: pick(
        "We're about #{pace_pct.abs}% behind the usual pace. Want Iris to show you where the gaps are?",
        "Tickets are tracking #{pace_pct.abs}% under a normal day. Iris has the breakdown if you want a look.",
      ),
      url: "/nykitchen/analyst"
    }
  end

  # --- Trigger 2: no flyers printed in the last week ---

  def no_flyers_nudge
    return nil unless cooled_down?("no_flyers", 7)

    last = Setting.time("nyk_flyer_prints:last_at")
    if last.nil?
      # First run seeds the timestamp and stays quiet (filter-card pattern):
      # before this feature we never recorded print times, so nil does not
      # mean "never printed".
      Setting.touch_time("nyk_flyer_prints:last_at")
      return nil
    end
    return nil if last >= 7.days.ago

    {
      key: "no_flyers",
      title: pick(
        "No fresh flyers out this week",
        "The front desk might be due for new flyers",
      ),
      body: pick(
        "Nothing has gone to the printer in a week. Tap and Neon will have a new batch ready in seconds.",
        "Last print run was over a week ago. Want me to pull up this week's schedule to print?",
      ),
      url: "/nykitchen/display/print"
    }
  end

  # --- Trigger 3: an upcoming class is down to its last seats ---

  def almost_sold_out_nudge
    return nil unless cooled_down?("almost_sold_out", 3)

    snapshot = KitchenSnapshot.latest
    return nil unless snapshot

    event = snapshot.kitchen_events.upcoming
      .where("start_at <= ?", 10.days.from_now)
      .where(spots_left: 1..2)
      .order(:start_at).first
    return nil unless event

    seats = "#{event.spots_left} #{"seat".pluralize(event.spots_left)}"
    when_str = event.start_at.strftime("%-m/%-d")
    prompt = "Draft a social post to push the last #{seats} of #{event.name} on #{when_str}"

    {
      key: "almost_sold_out",
      title: "#{event.name} is almost full",
      body: pick(
        "Down to the last #{seats} for #{when_str}. Want a post to sell it out?",
        "Only #{seats} left for #{when_str}. One tap and we'll draft the announcement.",
      ),
      url: "/nykitchen/ask?q=#{ERB::Util.url_encode(prompt)}&go=1"
    }
  end

  def pick(*variants)
    variants.sample
  end
end
