class RankJobMatchesJob < ApplicationJob
  queue_as :default

  ENRICH_LIMIT     = 20  # max Claude enrichments per run (cost guard)
  ENRICH_MIN_SCORE = 55  # only spend credits on strong matches

  # Re-score every active job against Rich's profile (cheap, rule-based), then
  # AI-enrich the strongest not-yet-enriched matches. Scheduled daily after the
  # 6am scrape (see config/recurring.yml).
  def perform
    JobMatcher.reload_profile!

    active_ids = Job.active.pluck(:id)
    JobMatch.transaction do
      Job.active.find_each { |job| JobMatch.record!(job, JobMatcher.evaluate(job)) }
    end

    # Drop matches whose job is no longer active (also handled by FK cascade on
    # deletes, but jobs go inactive without being deleted).
    JobMatch.where.not(job_id: active_ids).delete_all

    enriched = enrich_top_matches
    Rails.logger.info("RankJobMatchesJob: scored #{active_ids.size} jobs, enriched #{enriched}")
  rescue => e
    Notification.notify!(
      level: "error", source: "job_match",
      title: "RankJobMatchesJob crashed",
      body: "#{e.class}: #{e.message}\n\n#{e.backtrace&.first(5)&.join("\n")}",
      telegram: true
    )
    raise
  end

  private

  def enrich_top_matches
    JobMatch.ranked
            .where(enriched_at: nil)
            .where("score >= ?", ENRICH_MIN_SCORE)
            .limit(ENRICH_LIMIT)
            .includes(:job)
            .count { |m| JobMatchEnricher.enrich!(m) }
  end
end
