require "test_helper"

class PagesMemberDashboardTest < ActionDispatch::IntegrationTest
  test "members see the fleet dashboard at /" do
    member = User.create!(email_address: "dash-#{SecureRandom.hex(4)}@example.com", role: "member")
    sign_in_as(member)
    get root_path
    assert_response :success
    assert_match(/What can a fleet do for you/, response.body)
    assert_match(/Smoke testing/, response.body)
  end

  test "admins see the marketing home, not the member dashboard" do
    admin = User.create!(email_address: "dash-admin-#{SecureRandom.hex(4)}@example.com", role: "admin")
    sign_in_as(admin)
    get root_path
    assert_response :success
    refute_match(/What can a fleet do for you/, response.body)
  end

  test "anonymous visitors see the marketing home, not the member dashboard" do
    get root_path
    assert_response :success
    refute_match(/What can a fleet do for you/, response.body)
  end

  test "pending request banner shows after submission" do
    member = User.create!(email_address: "dash-#{SecureRandom.hex(4)}@example.com", role: "member")
    member.fleet_requests.create!(services: "smoke", status: "pending")
    sign_in_as(member)
    get root_path
    assert_response :success
    assert_match(/Rich will reach out/, response.body)
  end
end
