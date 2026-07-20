require "test_helper"

class JobMatchDigestJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  # Fixtures (automation_engineer, senior_qa) are full-time, non-remote, and
  # have no Ruby, so they never match this digest's filter.
  def make_job(title:, category: "full_time", location: "Remote", desc: "", role_class: "traditional")
    job = Job.create!(
      title: title, company: "Acme", url: "https://example.com/#{SecureRandom.hex(6)}",
      source: "test", description: desc, category: category, location: location,
      role_class: role_class, active: true
    )
    JobMatch.record!(job, JobMatcher.evaluate(job))
    job
  end

  test "emails part-time remote Ruby test-automation roles to the profile recipient" do
    make_job(title: "Ruby SDET (Part-time)", category: "part_time",
             desc: "Remote ruby test automation, part-time contract")
    make_job(title: "Ruby SDET (Full-time)", category: "full_time",
             desc: "Remote ruby test automation")            # eligible but PT should win
    make_job(title: "Product Manager", desc: "no ruby, no testing here")  # irrelevant

    assert_emails 1 do
      JobMatchDigestJob.perform_now
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "botwhisperer@hey.com" ], mail.to
    assert_match(/part-time/i, mail.subject)
    assert_includes mail.body.encoded, "Ruby SDET (Part-time)"
    assert_not_includes mail.body.encoded, "Product Manager"
  end

  test "falls back to full-time remote Ruby test-automation when nothing part-time/contract" do
    make_job(title: "Ruby QA Engineer", category: "full_time",
             desc: "Remote ruby sdet test automation role, full time")

    assert_emails 1 do
      JobMatchDigestJob.perform_now
    end

    mail = ActionMailer::Base.deliveries.last
    assert_match(/full-time/i, mail.subject)
    assert_includes mail.body.encoded, "Ruby QA Engineer"
  end

  test "excludes non-remote and non-Ruby roles" do
    make_job(title: "Ruby SDET", location: "New York, NY", desc: "onsite ruby test automation")  # not remote
    make_job(title: "Java SDET", location: "Remote", desc: "remote java test automation")        # no ruby

    JobMatchDigestJob.perform_now
    mail = ActionMailer::Base.deliveries.last
    # both excluded -> nothing-new email
    assert_match(/nothing new/i, mail.subject)
  end
end
