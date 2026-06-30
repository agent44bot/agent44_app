# Hourly polls X + Bluesky for engagement metrics on recent WorkspacePosts.
# Limits to posts < 30 days old (engagement plateaus, no point hammering
# the API forever) and to posts where the last successful sync was > 50 min
# ago (so this job is idempotent if it fires twice). Per-post failures get
# logged and skipped; one bad post never blocks the rest.
class RefreshSocialMetricsJob < ApplicationJob
  queue_as :default

  REFRESH_WINDOW       = 30.days
  MIN_REFRESH_INTERVAL = 50.minutes

  # workspace_id: scope the refresh to one workspace (used by the manual
  #   "Refresh metrics" button on /workspaces/:slug).
  # force: bypass the MIN_REFRESH_INTERVAL gate (manual button only).
  def perform(workspace_id: nil, force: false)
    scope = WorkspacePost.where(status: "posted")
                         .where("posted_at > ?", REFRESH_WINDOW.ago)
                         .includes(:social_account)
    scope = scope.where(workspace_id: workspace_id) if workspace_id
    scope = scope.where("metrics_synced_at IS NULL OR metrics_synced_at < ?", MIN_REFRESH_INTERVAL.ago) unless force

    refreshed = 0
    scope.find_each do |post|
      refreshed += 1 if refresh_one(post)
    end
    refreshed
  end

  private

  def refresh_one(post)
    account = post.social_account
    return false unless account&.status == "active" && post.remote_id.present?

    metrics =
      case post.platform
      when "x"
        X::UserClient.new(account).fetch_metrics(post.remote_id)
      when "bluesky"
        at_uri = "at://#{account.external_id}/app.bsky.feed.post/#{post.remote_id}"
        Bluesky::UserClient.new(account).fetch_metrics(at_uri)
      end

    return false unless metrics

    # Snapshot the engagement counts before the update so we can tell members
    # about NEW activity. Skip the alert on a post's very first sync: there's no
    # prior baseline, so the whole current count would read as "new" and spam a
    # burst (especially right after this ships, when every old post syncs once).
    had_prior_sync = post.metrics_synced_at.present?
    before = ENGAGEMENT_FIELDS.keys.index_with { |f| post.public_send(f).to_i }

    post.update!(
      impressions:       metrics[:impressions].to_i,
      likes:             metrics[:likes].to_i,
      reposts:           metrics[:reposts].to_i,
      replies:           metrics[:replies].to_i,
      quotes:            metrics[:quotes].to_i,
      bookmarks:         metrics[:bookmarks].to_i,
      metrics_synced_at: Time.current
    )

    notify_new_engagement(post, before) if had_prior_sync
    true
  rescue => e
    Rails.logger.warn("RefreshSocialMetricsJob: WorkspacePost ##{post.id} failed: #{e.class}: #{e.message}")
    false
  end

  # Engagement metrics we alert on (impressions/bookmarks are passive, skipped),
  # mapped to their singular human label for the push copy.
  ENGAGEMENT_FIELDS = { likes: "like", reposts: "repost", quotes: "quote", replies: "reply" }.freeze

  # Push a "your post got new engagement" alert to every workspace member when
  # any tracked metric went up since the last sync. Per-user and per-workspace
  # push opt-outs are honored inside Notification.notify!. One push per post per
  # refresh; the body summarizes all the deltas (e.g. "+2 likes, +1 reply").
  def notify_new_engagement(post, before)
    deltas = ENGAGEMENT_FIELDS.keys.filter_map do |f|
      gained = post.public_send(f).to_i - before[f]
      [ f, gained ] if gained.positive?
    end
    return if deltas.empty?

    workspace = post.workspace
    return unless workspace
    return if quiet_hours?(workspace) # no overnight pings (metrics still update)

    summary  = deltas.map { |f, n| "+#{n} #{ENGAGEMENT_FIELDS[f].pluralize(n)}" }.join(", ")
    platform = post.platform == "x" ? "X" : post.platform.titleize
    snippet  = post.body.to_s.gsub(/\s+/, " ").strip.truncate(80)

    social_recipients(workspace).find_each do |user|
      Notification.notify!(
        level:         "info",
        source:        "social_engagement",
        title:         "#{summary} on your #{platform} post",
        body:          snippet.presence,
        apns:          true,
        apns_url:      social_path_for(workspace),
        apns_subtitle: social_agent_label(workspace),
        apns_user:     user,
        workspace:     workspace
      )
    end
  end

  # Quiet hours: no social pushes from 9:00 PM to 8:00 AM in the workspace's
  # local time (NY Kitchen is Eastern). Metrics still refresh; only the alert
  # is held. Overnight engagement just won't ping (it shows in the counts).
  QUIET_START_HOUR = 21 # 9 PM
  QUIET_END_HOUR   = 8  # 8 AM
  def quiet_hours?(workspace)
    tz   = workspace.timezone.presence || "Eastern Time (US & Canada)"
    hour = Time.current.in_time_zone(tz).hour
    hour >= QUIET_START_HOUR || hour < QUIET_END_HOUR
  end

  # Who receives social engagement pushes for a workspace. If the Setting
  # "social_engagement:recipients:<workspace_id>" holds a comma-separated list
  # of user IDs, only those members are notified (e.g. NY Kitchen -> only Rich);
  # otherwise every member gets them (the default).
  def social_recipients(workspace)
    ids = Setting.get("social_engagement:recipients:#{workspace.id}").to_s.split(",").map(&:strip).reject(&:blank?)
    ids.empty? ? workspace.users : workspace.users.where(id: ids)
  end

  # In-app deep link to the workspace's social page. NY Kitchen has its own
  # slug-baked route; everything else uses the generic workspace social path.
  def social_path_for(workspace)
    helpers = Rails.application.routes.url_helpers
    workspace.slug == "nykitchen" ? helpers.nyk_social_path : helpers.social_workspace_path(workspace.slug)
  end

  # Subtitle on the push: the social agent's name (NY Kitchen's is "Echo").
  def social_agent_label(workspace)
    name = workspace.agent_for("social")&.display_name.presence
    name ||= "Echo" if workspace.slug == "nykitchen"
    "#{name || 'Social'} · #{workspace.name}"
  end
end
