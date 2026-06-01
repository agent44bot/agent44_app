class JobMatchMailer < ApplicationMailer
  # Daily digest of Rich's top job matches. `matches` is an array of JobMatch
  # records (ranked, jobs preloaded). `fresh_ids` is the set of match ids newly
  # scraped since the last run (flagged "NEW" in the email). Built by
  # JobMatchDigestJob.
  def daily_matches(matches, recipient:, fresh_ids: nil)
    @matches     = Array(matches)
    @fresh_ids   = fresh_ids || Set.new
    @fresh_count = @matches.count { |m| @fresh_ids.include?(m.id) }
    @profile     = JobMatcher.profile["candidate"] || {}
    top = @matches.first&.job

    subject =
      if @matches.empty?
        "Your job matches"
      else
        "#{@matches.size} top job #{'match'.pluralize(@matches.size)}, top: #{top.title.to_s.truncate(46)}"
      end

    mail(to: recipient, subject: subject)
  end
end
