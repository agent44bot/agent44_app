class RankJobMatchesJob < ApplicationJob
  queue_as :default

  # Re-score every active job against Rich's profile (cheap, rule-based). No AI
  # tokens are spent here. Enrichment (the AI "why it fits" / pitch / lead-skills
  # blurbs) was removed so the pipeline only spends AI on the apply process
  # itself: the cover letter, generated on demand when Rich opens a role's apply
  # kit (see CoverLetterGenerator). Scheduled daily after the 6am scrape.
  def perform
    JobMatcher.reload_profile!

    active_ids = Job.active.pluck(:id)
    JobMatch.transaction do
      Job.active.find_each { |job| JobMatch.record!(job, JobMatcher.evaluate(job)) }
    end

    # Drop matches whose job is no longer active (also handled by FK cascade on
    # deletes, but jobs go inactive without being deleted).
    JobMatch.where.not(job_id: active_ids).delete_all

    Rails.logger.info("RankJobMatchesJob: scored #{active_ids.size} jobs (rule-based only, no AI)")
  rescue => e
    Notification.notify!(
      level: "error", source: "job_match",
      title: "RankJobMatchesJob crashed",
      body: "#{e.class}: #{e.message}\n\n#{e.backtrace&.first(5)&.join("\n")}",
      telegram: true
    )
    raise
  end
end
