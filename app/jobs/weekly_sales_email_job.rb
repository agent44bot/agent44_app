class WeeklySalesEmailJob < ApplicationJob
  queue_as :default

  # Sunday-evening sales recap from the Analyst Agent. Goes to everyone who
  # belongs to the NY Kitchen workspace (any membership role), resolved to
  # emails at send time. Members without an email on file are skipped.
  def perform
    workspace = Workspace.find_by(slug: "nykitchen")
    unless workspace
      Rails.logger.info("WeeklySalesEmailJob: no nykitchen workspace, skipping")
      return
    end

    recipients = workspace.users.filter_map { |u| u.email_address.presence }.uniq
    if recipients.empty?
      Rails.logger.info("WeeklySalesEmailJob: no workspace members with an email, skipping")
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
  # carson: false skips the Carson intro (a paid Claude call) — used by the
  # admin report preview so eyeballing the report doesn't burn tokens. The
  # real Sunday send leaves it true.
  def self.build_summary(snapshot, carson: true)
    today = Date.current
    # Include sold-out classes (their tickets are fully booked revenue) so the
    # headline matches the Analyst dashboard's "All upcoming" rollup.
    upcoming = snapshot.kitchen_events.upcoming.to_a
    roll     = KitchenSnapshot.revenue_rollup(upcoming)

    # This week = Monday→Sunday (Lora's preference). The recap sends Sunday
    # evening, so on send day this is the full Mon-Sun week that just finished;
    # a mid-week preview shows the week so far.
    week_start = today.beginning_of_week(:monday)
    # Day-over-day sum (not endpoint diff) so "Booked this week" counts every
    # ticket sold this week, including classes that already ran, and matches
    # the weekly-tickets chart. Prior week is the full Mon-Sun before this one.
    bw = KitchenSnapshot.bookings_daily_total(week_start, today)
    pw = KitchenSnapshot.bookings_daily_total(week_start - 7, week_start - 1)

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
      movers:           KitchenSnapshot.bookings_between(today - 7, today).first(3),
      newly_sold_out:   KitchenSnapshot.newly_sold_out_since(today - 7),
      empty_last_week:  KitchenSnapshot.classes_ended_between(today - 7, today)
                          .select { |e| !e.truly_sold_out? && e.spots_left.to_i >= 3 }
                          .sort_by { |e| -e.spots_left.to_i }.first(5),
      periods:          KitchenSnapshot.period_rollups(snapshot),
      weekly_tickets:   KitchenSnapshot.tickets_sold_by_week,
      selling_fastest:  KitchenSnapshot.selling_fastest(snapshot: snapshot, limit: 3),
      needs_a_push:     KitchenSnapshot.needs_a_push(snapshot: snapshot, limit: 3),
      # Argus (Test) + Scout (Data) weekly ops briefs.
      argus:            SmokeTestRun.window_stats(:nyk_nav, today - 7, today),
      scout:            SmokeTestRun.window_stats(:nyk_scrape, today - 7, today)
                          .merge(snapshots: KitchenSnapshot.where(taken_on: (today - 7)..today).count),
      # Sam (List) calendar churn + Echo (Social) posting, this week.
      sam:              KitchenSnapshot.calendar_churn(today - 7),
      echo:             weekly_social(today - 7),
      # Neon (Display) in-store screen uptime this week.
      neon:             { last_seen_at:   Setting.time("nyk_display:last_seen_at"),
                          days_seen:      DisplayHeartbeat.days_seen(since: today - 6),
                          window_days:    7,
                          tracking_since: DisplayHeartbeat.tracking_since },
      # Cellar (Inventory): stock on hand, low-stock count, and this week's
      # box-in / bottle-out movement.
      cellar:           cellar_brief(today - 7),
      # Carson's "what's new this week" curated owner-facing changelog.
      changelog:        NykChangelog.recent(since: today - 7)
    }
    data[:headline] = carson ? carson_intro(data) : nil # Carson hosts the report (skipped on preview)
    data
  end

  # Cellar's weekly inventory brief: units on hand, low-stock count, and this
  # week's received (box-in) / removed (bottle-out) movement. Returns a :setup
  # state until the first item is added — the agent still appears in the roster
  # as "coming online" rather than vanishing. nil only if the table is absent.
  def self.cellar_brief(since)
    return nil unless ActiveRecord::Base.connection.table_exists?("inventory_items")
    item_count = InventoryItem.count
    return { items: 0, setup: true } if item_count.zero?

    on_hand = InventoryItem.on_hand_by_item
    low     = InventoryItem.all.count { |i| i.low_stock?(on_hand[i.id].to_i) }
    wk      = InventoryMovement.where("occurred_at >= ?", since.beginning_of_day)
    {
      setup:         false,
      items:         item_count,
      units:         on_hand.values.sum,
      low_stock:     low,
      received:      wk.inbound.sum(:quantity),
      removed:       wk.outbound.sum(:quantity),
      moves:         wk.count,
      last_activity: InventoryMovement.maximum(:occurred_at)
    }
  end

  # Echo's weekly social brief: posts published + engagement since `since`.
  # Returns nil when the workspace has no connected accounts (Echo's idle, so
  # the report just omits its brief). by_platform is { "x" => n, ... }.
  def self.weekly_social(since)
    ws = Workspace.find_by(slug: "nykitchen")
    return nil unless ws && ws.social_accounts.active.exists?
    posts = ws.workspace_posts.posted.where("posted_at >= ?", since.beginning_of_day)
    {
      accounts:    ws.social_accounts.active.count,
      posts:       posts.count,
      by_platform: posts.group(:platform).count,
      likes:       posts.sum(:likes),
      reposts:     posts.sum(:reposts),
      replies:     posts.sum(:replies)
    }
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
    argus = data[:argus] || {}; scout = data[:scout] || {}; sam = data[:sam] || {}; echo = data[:echo]; neon = data[:neon] || {}
    sold_out = Array(data[:newly_sold_out]).first(3).map(&:name).join("; ")
    at_risk_count = Array(data[:needs_a_push]).size
    at_risk  = Array(data[:needs_a_push]).first(2).map { |r| r[:event].name }.join("; ")

    prompt = <<~TXT
      You are Carson, the composed British butler who oversees New York Kitchen's team of AI agents and presents their week to the proprietor. Write 2 short sentences (about 35 words total) to open the weekly team report, warm and dignified, lightly butlerly without caricature, specific to the facts below. No salutation, no emoji, no quotes; just the remarks, leading with what matters most. Lead with sales and mention at most one other genuinely notable item, and do not list every agent. Use numerals for every figure (e.g. $6,384, 53%, 5 classes) and plain modern wording (avoid archaic terms like "whilst"). Do not use em dashes or en dashes; use commas, colons, or separate sentences. State only the facts below. Never invent counts, totals, or labels, and keep "booked this week" distinct from the overall pipeline. Treat any monitoring check "failures" as transient checker hiccups, never call them customer-facing outages, a "site failure rate", or "critical".
      This week across the team:
      - Sales (Iris): $#{bw[:revenue].to_i} booked in the last 7 days (#{wow}). The full pipeline is $#{data[:rev_total].to_i} across #{data[:total_upcoming]} upcoming classes, of which $#{data[:rev_sold].to_i} (#{data[:rev_total].to_f.positive? ? (100.0 * data[:rev_sold] / data[:rev_total]).round : 0}%) is booked so far. (The pipeline is the $#{data[:rev_total].to_i} total. Do NOT call the $#{data[:rev_sold].to_i} booked figure "the pipeline".)
      - Site checks (Argus): #{argus[:passed]} of #{argus[:total]} automated checks completed#{argus[:failed].to_i.positive? ? " (#{argus[:failed]} transient checker hiccups, not real outages)" : "; all clear"}.
      - Data (Scout): #{scout[:snapshots]} snapshots, #{scout[:passed]}/#{scout[:total]} scrape runs passed.
      - Calendar (Sam): #{sam[:added].to_i} classes added, #{sam[:removed].to_i} removed, #{sam[:price_changes].to_i} price changes.
      - Social (Echo): #{echo ? "#{echo[:posts]} posts published, #{echo[:likes]} likes" : "not in use"}.
      - In-store screen (Neon): #{neon[:last_seen_at] ? "live #{neon[:days_seen]}/7 days, last seen #{neon[:last_seen_at].to_date == Date.current ? 'today' : 'earlier'}" : "no signal"}.
      - Newly sold out: #{sold_out.presence || 'none'}.
      - Behind pace: #{at_risk_count} #{'class'.pluralize(at_risk_count)}#{at_risk.present? ? " (e.g. #{at_risk})" : ''}.
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
