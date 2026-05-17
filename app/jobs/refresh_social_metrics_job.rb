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

    post.update!(
      impressions:       metrics[:impressions].to_i,
      likes:             metrics[:likes].to_i,
      reposts:           metrics[:reposts].to_i,
      replies:           metrics[:replies].to_i,
      quotes:            metrics[:quotes].to_i,
      bookmarks:         metrics[:bookmarks].to_i,
      metrics_synced_at: Time.current
    )
    true
  rescue => e
    Rails.logger.warn("RefreshSocialMetricsJob: WorkspacePost ##{post.id} failed: #{e.class}: #{e.message}")
    false
  end
end
