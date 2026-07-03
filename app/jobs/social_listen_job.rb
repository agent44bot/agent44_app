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

  # Curated, low-noise query set (NYK / Finger Lakes focused for now).
  DEFAULT_QUERIES = [
    "New York Kitchen Canandaigua",
    "Canandaigua cooking",
    "Finger Lakes cooking class",
    "Rochester cooking class",
    "Rochester date night ideas",
    "Finger Lakes foodie"
  ].freeze

  MIN_SCORE       = 40 # below this we don't store the lead (cuts noise)
  MAX_NEW_PER_RUN = 15 # cap the AI calls (and cost) per run

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

    candidates = (bluesky_candidates(ws) + reddit_candidates)
                 .uniq { |c| [ c[:platform], c[:external_id] ] }
                 .reject { |c| ws.social_leads.exists?(platform: c[:platform], external_id: c[:external_id]) }
                 .sort_by { |c| -(c[:posted_at]&.to_i || 0) } # freshest first
                 .first(MAX_NEW_PER_RUN)

    scout = SocialAi::LeadScout.new(workspace: ws)
    candidates.each { |c| store_lead(ws, scout, c) }
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
      client.search_posts(q, limit: 15)
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
