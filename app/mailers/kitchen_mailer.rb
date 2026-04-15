class KitchenMailer < ApplicationMailer
  def daily_digest(digest, recipients:)
    @today = digest[:today]
    @today_events = digest[:today_events]
    @tomorrow_events = digest[:tomorrow_events]
    @week_events = digest[:week_events]
    @newly_sold_out = digest[:newly_sold_out]
    @newly_added = digest[:newly_added]
    @removed = digest[:removed]
    @price_changes = digest[:price_changes]
    @total_upcoming = digest[:total_upcoming]
    @total_sold_out = digest[:total_sold_out]

    mail(
      to: recipients,
      subject: "NY Kitchen — #{@today_events.size} today, #{@tomorrow_events.size} tomorrow"
    )
  end
end
