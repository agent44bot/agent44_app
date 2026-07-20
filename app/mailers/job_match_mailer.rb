class JobMatchMailer < ApplicationMailer
  # Daily digest of Rich's top job matches. `matches` is an array of JobMatch
  # records (ranked, jobs preloaded). `fresh_ids` is the set of match ids newly
  # scraped since the last run (flagged "NEW" in the email). Built by
  # JobMatchDigestJob.
  def daily_matches(matches, recipient:, fresh_ids: nil, fallback: false, other_matches: nil)
    @matches       = Array(matches)
    @other_matches = Array(other_matches)
    @fresh_ids     = fresh_ids || Set.new
    @fresh_count   = @matches.count { |m| @fresh_ids.include?(m.id) }
    @fallback      = fallback
    @profile     = JobMatcher.profile["candidate"] || {}
    top = @matches.first&.job

    kind = @fallback ? "full-time" : "part-time"
    subject =
      if @matches.empty?
        "Ruby test automation: nothing new today"
      else
        "#{@matches.size} #{kind} remote Ruby test-automation #{'role'.pluralize(@matches.size)}, top: #{top.title.to_s.truncate(40)}"
      end

    mail(to: recipient, subject: subject)
  end
end
