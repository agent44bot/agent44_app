class WeeklySalesEmailJob < ApplicationJob
  queue_as :default

  # Sunday-evening sales recap from the Analyst Agent. Recipients are the
  # workspace members who opted in on the Analyst dashboard (subscriber IDs
  # stored on the analyst WorkspaceAgent), resolved to emails at send time.
  def perform
    workspace = Workspace.find_by(slug: "nykitchen")
    unless workspace
      Rails.logger.info("WeeklySalesEmailJob: no nykitchen workspace, skipping")
      return
    end

    agent = workspace.agent_for("analyst")
    ids = Array(agent.setting(:weekly_email_subscriber_ids)).map(&:to_i)
    recipients = User.where(id: ids).filter_map { |u| u.email_address.presence }.uniq
    if recipients.empty?
      Rails.logger.info("WeeklySalesEmailJob: no subscribers opted in, skipping")
      return
    end

    deliver_to(recipients)
  rescue => e
    Notification.notify!(
      level: "error",
      source: "kitchen_email",
      title: "WeeklySalesEmailJob crashed",
      body: "#{e.class}: #{e.message}\n\n#{e.backtrace&.first(5)&.join("\n")}",
      telegram: true
    )
    raise
  end

  # Build the recap from the latest snapshot and email it to `recipients`.
  # Extracted so a one-off test send hits the exact same content as the real
  # job, e.g. WeeklySalesEmailJob.new.deliver_to(["you@example.com"]).
  # No-op (logs) when there's no snapshot yet.
  def deliver_to(recipients)
    snapshot = KitchenSnapshot.latest
    unless snapshot
      Rails.logger.info("WeeklySalesEmailJob: no snapshot in DB, skipping")
      return
    end

    KitchenMailer.weekly_sales(self.class.build_summary(snapshot), recipients: recipients).deliver_now
    Rails.logger.info("WeeklySalesEmailJob: sent to #{recipients} (snapshot #{snapshot.taken_on})")
  end

  # The recap payload the mailer renders, derived from a snapshot. Class method
  # so both the scheduled run and a test send share one source of truth.
  def self.build_summary(snapshot)
    upcoming  = snapshot.kitchen_events.upcoming.reject(&:sold_out?)
    priced    = upcoming.select(&:capacity_known?)
    rev_sold  = priced.sum(&:revenue_sold)
    rev_total = priced.sum(&:revenue_total)

    {
      snapshot_date:    snapshot.taken_on,
      stale:            snapshot.taken_on != Date.current,
      total_upcoming:   upcoming.size,
      rev_sold:         rev_sold,
      rev_total:        rev_total,
      rev_left:         rev_total - rev_sold,
      rev_priced_count: priced.size,
      rev_proxy_count:  priced.count(&:capacity_via_proxy?),
      weekly_tickets:   KitchenSnapshot.tickets_sold_by_week,
      selling_fastest:  KitchenSnapshot.selling_fastest(snapshot: snapshot),
      needs_a_push:     KitchenSnapshot.needs_a_push(snapshot: snapshot)
    }
  end
end
