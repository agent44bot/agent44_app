require "test_helper"

class DeviceTokenTest < ActiveSupport::TestCase
  test "valid with token and platform" do
    dt = DeviceToken.new(token: "test-token-123", platform: "ios")
    assert dt.valid?
  end

  test "invalid without token" do
    dt = DeviceToken.new(platform: "ios")
    assert_not dt.valid?
  end

  test "invalid with duplicate token" do
    DeviceToken.create!(token: "unique-token", platform: "ios")
    dt = DeviceToken.new(token: "unique-token", platform: "ios")
    assert_not dt.valid?
  end

  test "active scope returns only active tokens" do
    active = DeviceToken.create!(token: "active-1", platform: "ios", active: true)
    DeviceToken.create!(token: "inactive-1", platform: "ios", active: false)

    assert_includes DeviceToken.active, active
    assert_equal 1, DeviceToken.active.count
  end

  test "defaults to active" do
    dt = DeviceToken.create!(token: "new-token", platform: "ios")
    assert dt.active?
  end
end
