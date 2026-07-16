require "test_helper"

# Admin "View as" impersonation must not leak into PageView analytics: while an
# admin is impersonating, their browsing would be attributed to the impersonated
# user (Current.user) and pollute that user's real activity feed.
class TrackableImpersonationTest < ActionDispatch::IntegrationTest
  UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15".freeze
  IP = "203.0.113.77".freeze

  setup do
    @admin  = User.create!(email_address: "imp-admin-#{SecureRandom.hex(4)}@example.com", role: "admin")
    @target = User.create!(email_address: "imp-target-#{SecureRandom.hex(4)}@example.com")
    sign_in_as @admin
  end

  test "the impersonate control action itself is not tracked" do
    assert_no_difference -> { PageView.count } do
      perform_enqueued_jobs do
        post impersonate_path(@target.id), headers: { "User-Agent" => UA, "Fly-Client-IP" => IP }
      end
    end
  end

  test "page views while impersonating are not recorded" do
    post impersonate_path(@target.id), headers: { "User-Agent" => UA, "Fly-Client-IP" => IP }
    assert_no_difference -> { PageView.count } do
      perform_enqueued_jobs do
        get root_path, headers: { "User-Agent" => UA, "Fly-Client-IP" => IP }
      end
    end
  end

  test "tracking resumes and attributes to the admin after impersonation stops" do
    post impersonate_path(@target.id), headers: { "User-Agent" => UA, "Fly-Client-IP" => IP }
    delete stop_impersonating_path, headers: { "User-Agent" => UA, "Fly-Client-IP" => IP }
    perform_enqueued_jobs do
      get root_path, headers: { "User-Agent" => UA, "Fly-Client-IP" => IP }
    end
    pv = PageView.where(path: "/").order(created_at: :desc).first
    assert pv, "expected tracking to resume after impersonation ended"
    assert_equal @admin.id, pv.user_id
  end
end
