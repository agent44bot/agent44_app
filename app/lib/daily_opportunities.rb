# The day's job selection shared by the morning digest email (JobMatchDigestJob)
# and the Today's Opportunities page (JobsController#opportunities), so both show
# exactly the same roles:
#   ruby     - remote Ruby test-automation, part-time/contract first; when none,
#              full-time remote Ruby test-automation (fallback: true)
#   other    - other (non-Ruby) part-time/contract remote roles
class DailyOpportunities
  RUBY_LIMIT  = 10
  OTHER_LIMIT = 15

  attr_reader :ruby, :other, :fallback

  def self.call
    target = JobMatch.ranked
                     .preload(job: :job_sources)
                     .joins(:job).merge(Job.active.remote.ruby_relevant.test_automation)

    ruby     = target.merge(Job.part_time_ish).limit(RUBY_LIMIT).to_a
    fallback = ruby.empty?
    ruby     = target.limit(RUBY_LIMIT).to_a if fallback

    other = JobMatch.ranked
                    .preload(job: :job_sources)
                    .joins(:job).merge(Job.active.remote.part_time_ish.non_ruby)
                    .limit(OTHER_LIMIT).to_a

    new(ruby: ruby, other: other, fallback: fallback)
  end

  def initialize(ruby:, other:, fallback:)
    @ruby = ruby
    @other = other
    @fallback = fallback
  end

  def all_matches
    ruby + other
  end
end
