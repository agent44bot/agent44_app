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

  test "ios and android scopes filter by platform" do
    ios = DeviceToken.create!(token: "ios-1", platform: "ios")
    android = DeviceToken.create!(token: "android-1", platform: "android")

    assert_equal [ ios ], DeviceToken.ios.to_a
    assert_equal [ android ], DeviceToken.android.to_a
  end

  test "for_user scope filters by user" do
    user = users(:one)
    other = users(:two)
    mine = DeviceToken.create!(token: "mine", platform: "ios", user: user)
    DeviceToken.create!(token: "theirs", platform: "ios", user: other)
    DeviceToken.create!(token: "orphan", platform: "ios")

    assert_equal [ mine ], DeviceToken.for_user(user).to_a
    assert_equal [ mine ], DeviceToken.for_user(user.id).to_a
  end
end
