class JobMatchDigestJob < ApplicationJob
  queue_as :default

  MIN_SCORE = 60   # only email genuinely worth-applying matches
  LIMIT     = 10
  FRESH_WINDOW = 26.hours  # "new since the last daily scrape"

  # Daily digest of fresh, strong matches for Rich. Runs after RankJobMatchesJob
  # (see config/recurring.yml). Skips quietly if nothing new cleared the bar.
  def perform
    recipient = JobMatcher.profile.dig("candidate", "email").presence || ENV["JOB_MATCH_RECIPIENT"]
    if recipient.blank?
      Rails.logger.info("JobMatchDigestJob: no recipient configured, skipping")
      return
    end

    matches = JobMatch.ranked
                      .preload(job: :job_sources)
                      .joins(:job).merge(Job.active)
                      .where("jobs.created_at >= ?", FRESH_WINDOW.ago)
                      .where("job_matches.score >= ?", MIN_SCORE)
                      .limit(LIMIT).to_a

    if matches.empty?
      Rails.logger.info("JobMatchDigestJob: no new strong matches, skipping")
      return
    end

    JobMatchMailer.daily_matches(matches, recipient: recipient).deliver_now
    Rails.logger.info("JobMatchDigestJob: emailed #{matches.size} matches to #{recipient}")
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
