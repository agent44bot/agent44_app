require "test_helper"

class ApnsPusherGatingTest < ActiveSupport::TestCase
  test "enabled_for? respects the user's iOS push preference" do
    assert ApnsPusher.enabled_for?(nil), "broadcast (no user) is always enabled"

    user = users(:one)
    user.update!(ios_push_enabled: true)
    assert ApnsPusher.enabled_for?(user)

    user.update!(ios_push_enabled: false)
    assert_not ApnsPusher.enabled_for?(user)
  end

  test "send_alert returns early when the user disabled iOS push" do
    user = users(:one)
    user.update!(ios_push_enabled: false)
    DeviceToken.create!(token: "ios-x", platform: "ios", user: user)
    assert_nil ApnsPusher.send_alert(Notification.create!(level: "info", source: "t", title: "T"), user: user)
  end
end
