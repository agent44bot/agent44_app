require "test_helper"

class FleetRequestTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "fleet-#{SecureRandom.hex(4)}@example.com", role: "member")
  end

  test "services_list parses comma-joined values" do
    req = @user.fleet_requests.create!(services: "smoke,social", status: "pending")
    assert_equal %w[smoke social], req.services_list
  end

  test "services_labels maps known keys to friendly labels" do
    req = @user.fleet_requests.create!(services: "smoke,custom", status: "pending")
    assert_equal ["Smoke testing", "Custom agent"], req.services_labels
  end

  test "blank services list returns []" do
    req = @user.fleet_requests.create!(services: "", status: "pending")
    assert_equal [], req.services_list
  end

  test "validates status inclusion" do
    req = @user.fleet_requests.build(services: "", status: "garbage")
    refute req.valid?
    assert_includes req.errors[:status], "is not included in the list"
  end
end
