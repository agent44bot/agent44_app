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

  # Twice-weekly team report (Monday and Friday), hosted by Carson. `summary` is built by
  # WeeklySalesEmailJob (each agent's week + Carson's intro). Method/template
  # keep the weekly_sales name for wiring; the content is the team report.
  def weekly_sales(summary, recipients:)
    @s = summary
    booked = ActiveSupport::NumberHelper.number_to_currency(summary.dig(:booked_week, :revenue).to_i, precision: 0)
    mail(
      to: recipients,
      subject: "NY Kitchen — your team's week · #{booked} booked"
    )
  end

  # One-click failure report a manager can forward to an outside developer.
  # Bundles the failed run's error, console output, and steps, with signed
  # links to the video, trace, and page source (no login needed). Artifacts
  # are linked, not attached, to keep the email small and deliverable.
  def smoke_failure_report(run, recipient:, note: nil, from_name: nil)
    @run       = run
    @note      = note.to_s.strip.presence
    @from_name = from_name.to_s.strip.presence
    @when_str  = run.started_at.in_time_zone("Eastern Time (US & Canada)").strftime("%b %-d, %Y at %-I:%M %p ET")
    @video_url       = run.video.attached?       ? rails_blob_url(run.video) : nil
    @trace_url       = run.trace.attached?       ? rails_blob_url(run.trace, disposition: "attachment") : nil
    @page_source_url = run.page_source.attached? ? rails_blob_url(run.page_source, disposition: "attachment") : nil
    mail(to: recipient, subject: "NY Kitchen test failure: #{run.name} (#{@when_str})")
  end
end
