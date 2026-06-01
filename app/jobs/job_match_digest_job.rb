class JobMatchDigestJob < ApplicationJob
  queue_as :default

  MIN_SCORE = 60   # only email genuinely worth-applying matches
  LIMIT     = 10
  FRESH_WINDOW = 26.hours  # "scraped since the last daily run" → flagged NEW

  # Daily digest of Rich's strongest matches. Always sends the top-ranked
  # matches (so the agent/FDE roles surface regardless of when they were
  # scraped), and flags which ones are newly scraped since the last run.
  # Earlier this filtered to the 26h-fresh set only, which meant a QA-heavy
  # scrape day could bury the top agent/FDE roles entirely.
  def perform
    recipient = JobMatcher.profile.dig("candidate", "email").presence || ENV["JOB_MATCH_RECIPIENT"]
    if recipient.blank?
      Rails.logger.info("JobMatchDigestJob: no recipient configured, skipping")
      return
    end

    matches = JobMatch.ranked
                      .preload(job: :job_sources)
                      .joins(:job).merge(Job.active)
                      .where("job_matches.score >= ?", MIN_SCORE)
                      .limit(LIMIT).to_a

    if matches.empty?
      Rails.logger.info("JobMatchDigestJob: no strong matches over score #{MIN_SCORE}, skipping")
      return
    end

    # Which of these were scraped since the last daily run → "NEW" in the email.
    fresh_ids = matches.select { |m| m.job.created_at >= FRESH_WINDOW.ago }.map(&:id).to_set

    JobMatchMailer.daily_matches(matches, recipient: recipient, fresh_ids: fresh_ids).deliver_now
    Rails.logger.info("JobMatchDigestJob: emailed #{matches.size} matches (#{fresh_ids.size} new) to #{recipient}")
  rescue => e
    Notification.notify!(
      level: "error", source: "job_match",
      title: "JobMatchDigestJob crashed",
      body: "#{e.class}: #{e.message}\n\n#{e.backtrace&.first(5)&.join("\n")}",
      telegram: true
    )
    raise
  end
end
