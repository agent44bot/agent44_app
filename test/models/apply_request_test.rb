require "test_helper"

class ApplyRequestTest < ActiveSupport::TestCase
  def job
    @job ||= Job.create!(title: "Ruby SDET", company: "Acme", url: "https://example.com/#{SecureRandom.hex(6)}",
                         source: "test", category: "contract", location: "Remote", active: true)
  end

  test "enqueue! creates a queued request, one row per job" do
    r1 = ApplyRequest.enqueue!(job)
    assert_equal "queued", r1.status
    assert r1.requested_at.present?

    r2 = ApplyRequest.enqueue!(job)
    assert_equal r1.id, r2.id
    assert_equal 1, ApplyRequest.where(job_id: job.id).count
  end

  test "re-enqueue resets an applied request back to queued" do
    r = ApplyRequest.enqueue!(job)
    r.update!(status: "applied", applied_at: Time.current)

    ApplyRequest.enqueue!(job)
    assert_equal "queued", r.reload.status
  end
end
