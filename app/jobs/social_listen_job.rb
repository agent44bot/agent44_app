# Echo's social listening. A few times a day, searches Bluesky + Reddit for
# local food / cooking conversations and mentions, scores each fresh post with
# SocialAi::LeadScout, and stores the good ones as SocialLeads for a human to
# review on the Echo page. Nothing is auto-replied.
#
# Off by default: does nothing until Setting "social_listen:slugs" lists a
# workspace slug (comma-separated). Enable with just "nykitchen" to start.
#
# Manual test from prod console: SocialListenJob.perform_now
class SocialListenJob < ApplicationJob
  queue_as :default

  # Place-anchored queries (not narrow phrases). Bluesky search AND-matches
  # every word, so multi-word phrases like "Finger Lakes cooking class" return
  # almost nothing recent. Broader local terms have real recent volume; the AI
  # scorer (SocialAi::LeadScout) filters the off-topic ones back out.
  DEFAULT_QUERIES = [
    "New York Kitchen Canandaigua", # brand mention
    "Canandaigua",
    "Finger Lakes food",
    "Finger Lakes wine",
    "Finger Lakes weekend",
    "Rochester food",
    "Rochester date night",
    "Buffalo food",
    "Syracuse food",
    "upstate New York foodie",
    "Western New York food"
  ].freeze

  MIN_SCORE       = 60 # below this we don't store the lead (only confident, on-topic hits)
  MAX_NEW_PER_RUN = 15 # cap the AI calls (and cost) per run
  MAX_AGE_DAYS    = 14 # only surface recent posts (skip stale search hits)

  def perform
    workspace_slugs.each { |slug| listen_for(slug) }
  end

  private

  def workspace_slugs
    Setting.get("social_listen:slugs").to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def listen_for(slug)
    ws = Workspace.find_by(slug: slug)
    return unless ws

    cutoff = MAX_AGE_DAYS.days.ago
    candidates = (bluesky_candidates(ws) + reddit_candidates)
                 .uniq { |c| [ c[:platform], c[:external_id] ] }
                 .select { |c| c[:posted_at] && c[:posted_at] >= cutoff } # recent only
                 .reject { |c| ws.social_leads.exists?(platform: c[:platform], external_id: c[:external_id]) }
                 .sort_by { |c| -c[:posted_at].to_i } # freshest first
                 .first(MAX_NEW_PER_RUN)

    scout = SocialAi::LeadScout.new(workspace: ws)
    new_leads = candidates.filter_map { |c| store_lead(ws, scout, c) }
    notify_new_leads(ws, new_leads)
  end

  # One push per run (not one per lead): tell the reviewers how many new
  # conversations are waiting, deep-linked to the Echo page. Sends any time of
  # day (24/7). Off until Setting "social_listen:notify_user_ids" names
  # recipients.
  def notify_new_leads(ws, leads)
    return if leads.empty?
    users = notify_users
    return if users.empty?

    top   = leads.max_by(&:score)
    title = leads.size == 1 ? "New conversation for #{ws.name}" : "#{leads.size} new conversations for #{ws.name}"
    body  = leads.size == 1 ? "#{top.platform_label}: #{top.text.to_s.truncate(90)}" : "Tap to review and reply on the Echo page."
    url   = Rails.application.routes.url_helpers.nyk_social_path

    users.each do |user|
      Notification.notify!(
        level: :info, source: "echo", title: title, body: body,
        apns: true, apns_user: user, workspace: ws,
        apns_url: url, apns_subtitle: "Echo · Listening"
      )
    end
  end

  def notify_users
    ids = Setting.get("social_listen:notify_user_ids").to_s.split(",").map(&:strip).reject(&:blank?)
    ids.empty? ? [] : User.where(id: ids).to_a
  end

  def store_lead(ws, scout, candidate)
    result = scout.evaluate(candidate)
    return unless result && result.score >= MIN_SCORE

    ws.social_leads.create!(
      platform:      candidate[:platform],
      external_id:   candidate[:external_id],
      author:        candidate[:author],
      text:          candidate[:text],
      url:           candidate[:url],
      posted_at:     candidate[:posted_at],
      score:         result.score,
      reason:        result.reason,
      draft_reply:   result.reply,
      matched_query: candidate[:query],
      status:        "new"
    )
  rescue ActiveRecord::RecordNotUnique
    nil # raced with a concurrent run; the lead already exists
  end

  def bluesky_candidates(ws)
    account = ws.social_accounts.active.for_platform("bluesky").first
    return [] unless account

    client   = Bluesky::UserClient.new(account)
    own      = account.handle.to_s.delete_prefix("@")
    DEFAULT_QUERIES.flat_map do |q|
      client.search_posts(q, limit: 15, since: MAX_AGE_DAYS.days.ago)
            .reject { |p| p[:author].to_s == own } # don't surface our own posts
            .map { |p| p.merge(platform: "bluesky", query: q) }
    end
  end

  def reddit_candidates
    DEFAULT_QUERIES.flat_map do |q|
      Reddit::Search.posts(q, limit: 10).map { |p| p.merge(platform: "reddit", query: q) }
    end
  end
end
