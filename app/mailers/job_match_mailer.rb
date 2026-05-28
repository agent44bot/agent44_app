class JobMatchMailer < ApplicationMailer
  # Daily digest of new top job matches for Rich. `matches` is an array of
  # JobMatch records (ranked, with their jobs preloaded). Built by JobMatchDigestJob.
  def daily_matches(matches, recipient:)
    @matches = Array(matches)
    @profile = JobMatcher.profile["candidate"] || {}
    top = @matches.first&.job

    subject =
      if @matches.empty?
        "Your job matches"
      else
        "#{@matches.size} new job #{'match'.pluralize(@matches.size)} — top: #{top.title.to_s.truncate(46)}"
      end

    mail(to: recipient, subject: subject)
  end
end
