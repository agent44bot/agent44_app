class JobMatchDigestJob < ApplicationJob
  queue_as :default

  LIMIT       = 10
  OTHER_LIMIT = 15  # non-Ruby part-time/contract roles in the second section
  FRESH_WINDOW = 26.hours  # "scraped since the last daily run" → flagged NEW

  # Rich's morning digest: remote Ruby test-automation roles, part-time/contract
  # first. That niche is thin, so when nothing part-time/contract is available we
  # fall back to full-time remote Ruby test-automation (flagged full_time in the
  # email) rather than send nothing — his call. The role-match score only orders
  # within the filtered set; it is not a gate (a pure Ruby QA role can score low
  # under the FDE-leaning profile yet still be exactly what he wants).
  def perform
    recipient = JobMatcher.profile.dig("candidate", "email").presence || ENV["JOB_MATCH_RECIPIENT"]
    if recipient.blank?
      Rails.logger.info("JobMatchDigestJob: no recipient configured, skipping")
      return
    end

    target = JobMatch.ranked
                     .preload(job: :job_sources)
                     .joins(:job).merge(Job.active.remote.ruby_relevant.test_automation)

    matches  = target.merge(Job.part_time_ish).limit(LIMIT).to_a
    fallback = matches.empty?
    matches  = target.limit(LIMIT).to_a if fallback  # full-time remote Ruby QA

    # Second section: all other (non-Ruby) part-time/contract remote roles, so
    # Rich sees the adjacent contract market in other stacks.
    other = JobMatch.ranked
                    .preload(job: :job_sources)
                    .joins(:job).merge(Job.active.remote.part_time_ish.non_ruby)
                    .limit(OTHER_LIMIT).to_a

    # Which of these were scraped since the last daily run → "NEW" in the email.
    fresh_ids = (matches + other).select { |m| m.job.created_at >= FRESH_WINDOW.ago }.map(&:id).to_set

    JobMatchMailer.daily_matches(matches, recipient: recipient, fresh_ids: fresh_ids,
                                 fallback: fallback, other_matches: other).deliver_now
    Rails.logger.info("JobMatchDigestJob: emailed #{matches.size} #{fallback ? 'full-time fallback' : 'part-time/contract'} Ruby + #{other.size} other part-time/contract to #{recipient}")
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
