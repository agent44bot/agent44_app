class KitchenMailer < ApplicationMailer
  def daily_digest(digest, recipients:)
    @today = digest[:today]
    @current_week_events = digest[:current_week_events]
    @week1_events = digest[:week1_events]
    @week2_events = digest[:week2_events]
    @week3_events = digest[:week3_events]
    @newly_sold_out = digest[:newly_sold_out]
    @newly_added = digest[:newly_added]
    @removed = digest[:removed]
    @price_changes = digest[:price_changes]
    @total_upcoming = digest[:total_upcoming]
    @total_sold_out = digest[:total_sold_out]
    @snapshot_date  = digest[:snapshot_date]
    @stale_data     = digest[:stale_data]
    @selling_fastest = digest[:selling_fastest] || []
    @needs_a_push    = digest[:needs_a_push] || []

    mail(
      to: recipients,
      subject: "NY Kitchen — #{@week1_events.size} next week · #{@total_upcoming} upcoming"
    )
  end

  # Friday morning sales recap from the Analyst Agent. `summary` is built by
  # WeeklySalesEmailJob (revenue rollup + leaderboards + weekly trend).
  def weekly_sales(summary, recipients:)
    @s = summary
    sold   = ActiveSupport::NumberHelper.number_to_currency(summary[:rev_sold], precision: 0)
    left_k = (summary[:rev_left] / 1000.0).round
    mail(
      to: recipients,
      subject: "NY Kitchen weekly sales — #{sold} sold · ~$#{left_k}K still to sell"
    )
  end
end
