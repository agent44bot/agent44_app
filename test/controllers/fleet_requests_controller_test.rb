require "test_helper"

class FleetRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @member = User.create!(email_address: "fleet-req-member-#{SecureRandom.hex(4)}@example.com", role: "member")
  end

  test "create persists a row with the picked services + note" do
    sign_in_as(@member)
    assert_difference -> { FleetRequest.count }, 1 do
      post fleet_requests_path, params: { services: %w[smoke custom], note: "I run a tiny ecommerce store." }
    end
    req = FleetRequest.order(created_at: :desc).first
    assert_equal @member.id, req.user_id
    assert_equal "smoke,custom", req.services
    assert_equal "I run a tiny ecommerce store.", req.notes
    assert_equal "pending", req.status
    assert_redirected_to root_path
  end

  test "create rejects unknown service keys silently" do
    sign_in_as(@member)
    post fleet_requests_path, params: { services: %w[smoke not_a_real_service] }
    assert_equal "smoke", FleetRequest.last.services
  end

  test "unauthenticated request bounces to sign-in" do
    post fleet_requests_path, params: { services: %w[smoke] }
    assert_redirected_to %r{/session/new}
  end
end
