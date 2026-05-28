class JobMatchMailerPreview < ActionMailer::Preview
  # Preview at http://localhost:3000/rails/mailers/job_match_mailer/daily_matches
  # Uses real JobMatch data (prefers enriched matches so the AI pitch shows).
  def daily_matches
    matches = JobMatch.enriched.ranked.preload(job: :job_sources).limit(8).to_a
    matches = JobMatch.ranked.preload(job: :job_sources).limit(8).to_a if matches.empty?
    JobMatchMailer.daily_matches(matches, recipient: "preview@example.com")
  end
end
