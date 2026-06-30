require "test_helper"

# Our own traffic (the owner's residential IP) must not land in the visitor
# analytics. The exclusion matches the Fly-Client-IP client address, not
# request.remote_ip (which is fly's edge proxy).
class TrackableExcludedIpTest < ActionDispatch::IntegrationTest
  UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15".freeze
  EXCLUDED = Trackable::EXCLUDED_IPS.first

  test "request from an excluded client IP is not tracked" do
    assert_no_difference -> { PageView.where(path: "/").count } do
      perform_enqueued_jobs do
        get root_path, headers: { "User-Agent" => UA, "Fly-Client-IP" => EXCLUDED }
      end
    end
  end

  test "request from a normal client IP is still tracked" do
    perform_enqueued_jobs do
      get root_path, headers: { "User-Agent" => UA, "Fly-Client-IP" => "203.0.113.9" }
    end
    pv = PageView.where(path: "/").order(created_at: :desc).first
    assert pv, "expected a tracked page view for a non-excluded IP"
    assert_equal "203.0.113.9", pv.ip_address
  end
end
