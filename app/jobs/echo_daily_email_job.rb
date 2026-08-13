# Echo's daily conversations email, 3pm ET. Emails each workspace member the
# leads SocialListenJob has surfaced since the last send: the post, Echo's
# "why", the suggested reply, and links to act on it. Nothing is auto-replied,
# and a day with no new conversations sends nothing at all (no "0 today" mail).
#
# Sign-up is opt-out: every member of a listening workspace gets it until they
# turn it off in Settings or from the unsubscribe link in the email
# (WorkspaceMembership#echo_email_enabled).
#
# Manual test from prod console: EchoDailyEmailJob.perform_now
class EchoDailyEmailJob < ApplicationJob
  queue_as :default

  # How far back to look on the very first run for a workspace (before any
  # "last sent" stamp exists), so day one doesn't dump two weeks of backlog.
  FIRST_RUN_WINDOW = 1.day

  def perform
    workspace_slugs.each { |slug| email_for(slug) }
  end

  private

  # The same workspaces Echo listens for. A workspace that isn't being listened
  # to has nothing to email about.
  def workspace_slugs
    Setting.get("social_listen:slugs").to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def email_for(slug)
    ws = Workspace.find_by(slug: slug)
    return unless ws

    # Snapshot "now" before reading, and stamp that same instant afterwards: a
    # lead stored while this run is sending would otherwise land before the
    # stamp without being in this email, and never be mailed at all.
    run_at = Time.current
    since  = Setting.time(last_sent_key(slug)) || FIRST_RUN_WINDOW.ago
    # Only conversations still waiting on someone: anything already replied to
    # or dismissed on the Echo page is done, and re-mailing it is noise.
    leads = ws.social_leads.where(status: "new")
                .where("created_at > ? AND created_at <= ?", since, run_at)
                .order(score: :desc).to_a

    if leads.empty?
      Rails.logger.info("EchoDailyEmailJob: no new conversations for #{slug} since #{since}, nothing sent")
      # Still stamp the run, so a quiet day doesn't widen tomorrow's window.
      Setting.set(last_sent_key(slug), run_at.iso8601)
      return
    end

    sent = 0
    ws.echo_email_memberships.each do |membership|
      sent += 1 if deliver(ws, leads, membership.user.email_address, membership)
    end
    extra_recipients(ws).each { |address| sent += 1 if deliver(ws, leads, address, nil) }

    Setting.set(last_sent_key(slug), run_at.iso8601)
    Rails.logger.info("EchoDailyEmailJob: #{leads.size} conversations for #{slug}, emailed #{sent} recipients")
  end

  # One bad address must not stop the rest of the workspace from being emailed,
  # and no failure may skip the "last sent" stamp (that would re-send today's
  # leads tomorrow), so each send is rescued individually.
  def deliver(ws, leads, address, membership)
    EchoMailer.new_leads(workspace: ws, leads: leads, recipient: address, membership: membership).deliver_now
    true
  rescue => e
    Rails.logger.error("EchoDailyEmailJob: send to #{address} failed: #{e.class}: #{e.message}")
    false
  end

  # Hand-configured addresses that aren't workspace members (an agency inbox, a
  # personal address). Comma-separated, global or per workspace. These have no
  # membership to unsubscribe, so keep the list short.
  def extra_recipients(ws)
    raw = Setting.get("social_listen:notify_emails:#{ws.slug}").presence ||
          Setting.get("social_listen:notify_emails")
    member_addresses = ws.echo_email_memberships.filter_map { |m| m.user.email_address&.downcase }
    raw.to_s.split(",").map(&:strip).reject(&:blank?)
       .reject { |a| member_addresses.include?(a.downcase) } # don't double-email a member
  end

  def last_sent_key(slug)
    "echo_email:last_sent_at:#{slug}"
  end
end
