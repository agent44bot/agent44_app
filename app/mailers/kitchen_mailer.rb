class KitchenMailer < ApplicationMailer
  def daily_digest(digest, recipients:)
    @today = digest[:today]
    @week1_events = digest[:week1_events]
    @week2_events = digest[:week2_events]
    @week3_events = digest[:week3_events]
    @week4_events = digest[:week4_events]
    @newly_sold_out = digest[:newly_sold_out]
    @newly_added = digest[:newly_added]
    @removed = digest[:removed]
    @price_changes = digest[:price_changes]
    @total_upcoming = digest[:total_upcoming]
    @total_sold_out = digest[:total_sold_out]

    mail(
      to: recipients,
      subject: "NY Kitchen — #{@week1_events.size} next week · #{@total_upcoming} upcoming"
    )
  end
end
