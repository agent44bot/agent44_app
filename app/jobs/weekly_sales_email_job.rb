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
    today = Date.current
    # Include sold-out classes (their tickets are fully booked revenue) so the
    # headline matches the Analyst dashboard's "All upcoming" rollup.
    upcoming = snapshot.kitchen_events.upcoming.to_a
    roll     = KitchenSnapshot.revenue_rollup(upcoming)

    # "This week" = trailing 7 days of booking activity (the recap sends Sunday
    # evening, so the calendar week that just started is empty — the week that
    # just ended is what matters).
    bw = KitchenSnapshot.bookings_total(today - 7, today)
    pw = KitchenSnapshot.bookings_total(today - 14, today - 7)

    data = {
      snapshot_date:    snapshot.taken_on,
      stale:            snapshot.taken_on != Date.current,
      total_upcoming:   upcoming.size,
      rev_sold:         roll[:sold],
      rev_total:        roll[:total],
      rev_left:         roll[:left],
      rev_priced_count: roll[:count],
      rev_proxy_count:  upcoming.select(&:capacity_known?).count(&:capacity_via_proxy?),
      booked_week:      { tickets: bw[:tickets], revenue: bw[:revenue],
                          prior_tickets: pw[:tickets], prior_revenue: pw[:revenue] },
      movers:           KitchenSnapshot.bookings_between(today - 7, today).first(5),
      newly_sold_out:   KitchenSnapshot.newly_sold_out_since(today - 7),
      empty_last_week:  KitchenSnapshot.classes_ended_between(today - 7, today)
                          .select { |e| !e.sold_out? && e.spots_left.to_i >= 3 }
                          .sort_by { |e| -e.spots_left.to_i }.first(5),
      periods:          KitchenSnapshot.period_rollups(snapshot),
      weekly_tickets:   KitchenSnapshot.tickets_sold_by_week,
      selling_fastest:  KitchenSnapshot.selling_fastest(snapshot: snapshot),
      needs_a_push:     KitchenSnapshot.needs_a_push(snapshot: snapshot),
      # Argus (Test) + Scout (Data) weekly ops briefs.
      argus:            SmokeTestRun.window_stats(:nyk_nav, today - 7, today),
      scout:            SmokeTestRun.window_stats(:nyk_scrape, today - 7, today)
                          .merge(snapshots: KitchenSnapshot.where(taken_on: (today - 7)..today).count)
    }
    data[:headline] = carson_intro(data) # Carson hosts the report
    data
  end

  # Carson (the butler/concierge) hosts the report: a short opening written by
  # Claude (haiku) with full context from every agent's week. Skipped in tests
  # and when no API key is set; failures degrade to no intro. Logged via
  # AiCallLogger (source nyk_team_report) so the spend is tracked.
  def self.carson_intro(data)
    return nil if Rails.env.test?
    api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
    return nil if api_key.blank?

    bw  = data[:booked_week] || {}
    wow = bw[:prior_revenue].to_i.positive? ?
      "#{(100.0 * (bw[:revenue].to_i - bw[:prior_revenue]) / bw[:prior_revenue]).round}% vs last week" :
      "no prior week to compare"
    argus = data[:argus] || {}; scout = data[:scout] || {}
    sold_out = Array(data[:newly_sold_out]).first(3).map(&:name).join("; ")
    at_risk  = Array(data[:needs_a_push]).first(2).map { |r| r[:event].name }.join("; ")

    prompt = <<~TXT
      You are Carson, the composed British butler who oversees New York Kitchen's team of AI agents and presents their week to the proprietor. Write 2 short sentences (about 35 words total) to open the weekly team report — warm and dignified, lightly butlerly without caricature, specific to the facts below. No salutation, no emoji, no quotes; just the remarks, leading with what matters most.
      This week across the team:
      - Sales (Iris): $#{bw[:revenue].to_i} booked this week (#{wow}); pipeline $#{data[:rev_sold].to_i} across #{data[:total_upcoming]} classes, #{data[:rev_total].to_f.positive? ? (100.0 * data[:rev_sold] / data[:rev_total]).round : 0}% sold.
      - Site checks (Argus): #{argus[:passed]}/#{argus[:total]} passed, #{argus[:fail_pct]}% failed.
      - Data (Scout): #{scout[:snapshots]} snapshots, #{scout[:passed]}/#{scout[:total]} scrape runs passed.
      - Newly sold out: #{sold_out.presence || 'none'}.
      - Behind pace: #{at_risk.presence || 'none'}.
    TXT

    client = Anthropic::Client.new(api_key: api_key)
    resp = client.messages.create(model: "claude-haiku-4-5", max_tokens: 160,
      messages: [ { role: "user", content: prompt } ])
    AiCallLogger.log!(resp, model: "claude-haiku-4-5", source: "nyk_team_report")
    resp.content.filter_map { |b| b.respond_to?(:text) ? b.text : b["text"] }.join.strip.presence
  rescue => e
    Rails.logger.warn("WeeklySalesEmailJob.carson_intro failed: #{e.class}: #{e.message}")
    nil
  end
end
