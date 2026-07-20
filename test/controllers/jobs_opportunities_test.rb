require "test_helper"

class JobsOpportunitiesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "apply-admin-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @job = Job.create!(
      title: "Ruby SDET", company: "Acme", url: "https://example.com/#{SecureRandom.hex(6)}",
      source: "test", category: "contract", location: "Remote",
      description: "remote ruby test automation contract", role_class: "traditional", active: true
    )
    JobMatch.record!(@job, JobMatcher.evaluate(@job))
  end

  test "opportunities requires sign-in" do
    get opportunities_jobs_path
    assert_redirected_to "/sign_in"
  end

  test "opportunities is blocked for authenticated non-admins" do
    non_admin = User.create!(email_address: "plain-#{SecureRandom.hex(4)}@example.com", role: "user")
    sign_in_as(non_admin)
    get opportunities_jobs_path
    assert_response :redirect
    assert_no_match(/Today's Opportunities/, response.body)
  end

  test "admin sees the opportunities page with the role" do
    sign_in_as(@admin)
    get opportunities_jobs_path
    assert_response :success
    assert_select "h1", /Today's Opportunities/
    assert_match "Ruby SDET", response.body
  end

  test "enqueue_apply queues the job for the runner" do
    sign_in_as(@admin)
    assert_difference -> { ApplyRequest.count }, 1 do
      post enqueue_apply_job_path(@job)
    end
    assert_redirected_to opportunities_jobs_path
    assert_equal "queued", ApplyRequest.find_by(job_id: @job.id).status
  end

  test "enqueue_apply is blocked for authenticated non-admins" do
    non_admin = User.create!(email_address: "plain2-#{SecureRandom.hex(4)}@example.com", role: "user")
    sign_in_as(non_admin)
    post enqueue_apply_job_path(@job)
    assert_response :redirect
    assert_nil ApplyRequest.find_by(job_id: @job.id)
  end
end
