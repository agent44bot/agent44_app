# frozen_string_literal: true

# Shared computation of the NYK agent-fleet status summary, used by both
# KitchenAi::AskAgent (baked into its system prompt) and KitchenAi::AgenticAgent
# (exposed as the get_fleet_status read tool). Extracted so both read identical
# numbers — previously AgenticAgent reached into AskAgent's private method.
#
# All methods are pure reads against current DB state; no instance/user context.
module KitchenAi
  module FleetStatus
    module_function

    # Compact summary of every sibling agent in the NYK fleet. Mirrors the
    # windowed stats the hub computes so answers match what Lora sees on
    # the dashboard.
    def summary
      workspace = Workspace.find_by(slug: "nykitchen")
      now = Time.current
      this_week_start = now.beginning_of_week(:sunday)

      [
        list_agent(workspace),
        data_agent(this_week_start),
        test_agent(this_week_start),
        display_agent(workspace),
        social_agent(workspace, this_week_start)
      ].compact.join("\n\n")
    end

    def list_agent(_workspace)
      snapshot = KitchenSnapshot.latest
      return nil unless snapshot
      upcoming = snapshot.kitchen_events.upcoming.count
      sold_out = snapshot.kitchen_events.upcoming.count(&:sold_out?)
      this_week_actuals = KitchenSnapshot.tickets_sold_this_week_by_wday
                                          .values.compact.sum.to_i
      [
        "List Agent (calendar of upcoming classes):",
        "- #{upcoming} upcoming classes, #{sold_out} sold out",
        "- Tickets sold so far this week: #{this_week_actuals}",
        "- Snapshot date: #{snapshot.taken_on.strftime('%a %b %-d')}"
      ].join("\n")
    end

    def data_agent(this_week_start)
      scrape      = SmokeTestRun.nyk_scrape
      last_scrape = scrape.where(status: %w[passed failed]).order(started_at: :desc).first
      week_count  = scrape.where("started_at >= ?", this_week_start).where(status: %w[passed failed]).count
      [
        "Data Agent (scrapes the source calendar every 3h):",
        "- This week: #{week_count} successful scrape runs",
        "- Last scrape: #{last_scrape&.started_at ? time_phrase(last_scrape.started_at) : 'never'} (#{last_scrape&.status || 'n/a'})"
      ].join("\n")
    end

    def test_agent(this_week_start)
      nav             = SmokeTestRun.nyk_nav
      week_runs       = nav.where("started_at >= ?", this_week_start).where(status: %w[passed failed])
      week_failed     = week_runs.where(status: "failed").count
      week_total      = week_runs.count
      d30_runs        = nav.where("started_at >= ?", 30.days.ago).where(status: %w[passed failed])
      d30_total       = d30_runs.count
      d30_failed      = d30_runs.where(status: "failed").count
      d30_fail_rate   = d30_total.zero? ? 0.0 : (d30_failed.to_f / d30_total * 100).round(1)
      last_passed     = nav.where(status: "passed").order(started_at: :desc).first
      last_failed     = nav.where(status: "failed").order(started_at: :desc).first
      recent_failures = nav.where(status: "failed").order(started_at: :desc).limit(5).to_a

      lines = [
        "Test Agent (hourly smoke checks on the calendar — round-trips the page looking for breakage):",
        "- This week: #{week_total} runs, #{week_failed} failed",
        "- Last 30 days: #{d30_total} runs, #{d30_failed} failed (#{d30_fail_rate}% fail rate)",
        "- Last passed: #{last_passed&.started_at ? time_phrase(last_passed.started_at) : 'never'}",
        "- Last failed: #{last_failed&.started_at ? time_phrase(last_failed.started_at) : 'never'}"
      ]
      if recent_failures.any?
        lines << "- Recent failures:"
        recent_failures.each do |r|
          msg = (r.error_message.to_s.presence || r.summary.to_s.presence || "(no message)").truncate(160).tr("\n", " ")
          lines << "    · #{r.started_at.in_time_zone('Eastern Time (US & Canada)').strftime('%a %b %-d %-l:%M%P')} — #{msg}"
        end
      end
      lines.join("\n")
    end

    def display_agent(workspace)
      agent = workspace&.agent_for("display")
      return nil unless agent
      visibility = agent.setting(:visibility) || "public"
      [
        "Display Agent (in-store TV slideshow at /nykitchen/display):",
        "- Visibility: #{visibility}",
        "- Cycles #{agent.setting(:slide_count) || 5} classes, #{agent.setting(:advance_seconds) || 10}s each",
        "- Auto-refreshes every #{agent.setting(:refresh_minutes) || 10} minutes",
        "- Also prints a paper handout (Display settings → Print)"
      ].join("\n")
    end

    def social_agent(workspace, this_week_start)
      return nil unless workspace
      accounts = workspace.social_accounts.order(:platform).to_a
      lines = [ "Echo, the Social Agent (drafts + publishes posts to connected accounts):" ]

      if accounts.empty?
        lines << "- No social accounts connected yet"
      else
        active_strs = accounts.map do |a|
          state = a.respond_to?(:active?) ? (a.active? ? "ok" : "needs re-auth") : "ok"
          handle = a.handle.to_s.presence ? " (#{a.handle})" : ""
          "#{a.platform.capitalize}#{handle} — #{state}"
        end
        lines << "- Connected: #{active_strs.join('; ')}"
      end

      posted_week = workspace.workspace_posts.where(status: "posted")
                              .where("posted_at >= ?", this_week_start).count
      drafts_week = workspace.workspace_drafts.where("created_at >= ?", this_week_start).count
      last_post   = workspace.workspace_posts.where(status: "posted").order(posted_at: :desc).first
      lines << "- This week: #{posted_week} posted, #{drafts_week} new drafts"
      lines << "- Last post: #{last_post&.posted_at ? time_phrase(last_post.posted_at) : 'never'}"
      lines.join("\n")
    end

    def time_phrase(t)
      delta = Time.current - t
      if delta < 1.hour
        "#{(delta / 60).round} min ago"
      elsif delta < 1.day
        "#{(delta / 3600).round} hours ago"
      elsif delta < 7.days
        "#{(delta / 86_400).round} days ago"
      else
        t.in_time_zone("Eastern Time (US & Canada)").strftime("%b %-d, %Y")
      end
    end
  end
end
