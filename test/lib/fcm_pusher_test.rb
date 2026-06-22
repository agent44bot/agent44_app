require "test_helper"

# FcmPusher must never hit the network in tests (no creds configured), and must
# honor the per-user android_push_enabled gate. We assert the safe-skip paths;
# the actual FCM HTTP call is covered manually against the real service.
class FcmPusherTest < ActiveSupport::TestCase
  def note
    Notification.create!(level: "info", source: "test", title: "Hi", body: "there")
  end

  test "enabled_for? is true for nil user (broadcast) and android-enabled users" do
    assert FcmPusher.enabled_for?(nil)
    user = users(:one)
    user.update!(android_push_enabled: true)
    assert FcmPusher.enabled_for?(user)
  end

  test "enabled_for? is false when the user turned Android push off" do
    user = users(:one)
    user.update!(android_push_enabled: false)
    assert_not FcmPusher.enabled_for?(user)
  end

  test "send_alert is a no-op when the user disabled Android push (no token query)" do
    user = users(:one)
    user.update!(android_push_enabled: false)
    DeviceToken.create!(token: "and-1", platform: "android", user: user)
    # Would raise if it tried to load credentials/send; the gate returns first.
    assert_nil FcmPusher.send_alert(note, user: user)
  end

  test "send_alert is a no-op with no android tokens" do
    user = users(:one)
    DeviceToken.create!(token: "ios-only", platform: "ios", user: user)
    assert_nil FcmPusher.send_alert(note, user: user)
  end

  test "send_alert is a safe no-op without FCM credentials" do
    user = users(:one)
    DeviceToken.create!(token: "and-2", platform: "android", user: user)
    # No FCM_SERVICE_ACCOUNT_JSON in the test env -> returns before any HTTP.
    assert_nil FcmPusher.send_alert(note, user: user)
  end
end
