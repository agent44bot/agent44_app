require "test_helper"

class RankJobMatchesJobTest < ActiveSupport::TestCase
  test "scores active jobs rule-based and spends no AI (no enrichment)" do
    job = Job.create!(
      title: "Ruby SDET", company: "Acme", url: "https://example.com/#{SecureRandom.hex(5)}",
      source: "test", category: "contract", location: "Remote",
      description: "remote ruby test automation", role_class: "traditional", active: true
    )

    RankJobMatchesJob.perform_now

    match = JobMatch.find_by(job_id: job.id)
    assert match, "active job should be scored"
    assert match.score.present?, "rule-based score should be set"
    assert_nil match.why, "no AI 'why it fits' blurb"
    assert_nil match.pitch, "no AI pitch"
    assert_nil match.enriched_at, "job should not be enriched"
  end
end
