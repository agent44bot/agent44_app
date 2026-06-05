require "test_helper"

# /jobs is an internal tool: every action requires sign-in (it was public and
# getting hammered by scrapers; see PR for the bot evidence).
class JobsAccessTest < ActionDispatch::IntegrationTest
  test "signed-out visitors are redirected to sign in" do
    get jobs_path
    assert_redirected_to sign_in_path
  end

  test "signed-out job detail is redirected too" do
    job = Job.first || Job.create!(title: "Test role", company: "Acme", url: "https://example.com/j1")
    get job_path(job)
    assert_redirected_to sign_in_path
  end

  test "signed-in admins can browse jobs" do
    sign_in_as(User.create!(email_address: "jobs-#{SecureRandom.hex(4)}@example.com", role: "admin"))
    get jobs_path
    assert_response :success
  end
end
