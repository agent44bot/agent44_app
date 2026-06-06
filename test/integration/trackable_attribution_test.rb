require "test_helper"

# Signed-in users must be attributed on PUBLIC pages too. Those actions skip
# require_authentication, so Trackable resumes the session itself; before the
# fix every public-page hit by a signed-in user logged as anonymous.
class TrackableAttributionTest < ActionDispatch::IntegrationTest
  test "signed-in user is attributed on a public page" do
    user = User.create!(email_address: "trk-#{SecureRandom.hex(4)}@example.com", role: "user")
    sign_in_as(user)
    perform_enqueued_jobs do
      get root_path, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15" }
    end
    pv = PageView.where(path: "/").order(created_at: :desc).first
    assert pv, "expected a tracked page view"
    assert_equal user.id, pv.user_id, "public-page hit should attribute to the signed-in user"
  end

  test "signed-out visitor on a public page stays anonymous" do
    perform_enqueued_jobs do
      get root_path, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15" }
    end
    pv = PageView.where(path: "/").order(created_at: :desc).first
    assert pv
    assert_nil pv.user_id
  end
end
