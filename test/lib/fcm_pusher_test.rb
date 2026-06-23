require "test_helper"
require "minitest/mock"

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

  test "enabled_for? is false when the user muted this workspace" do
    user = users(:one)
    ws = Workspace.create!(name: "WS", slug: "fcm-#{SecureRandom.hex(4)}", owner_id: user.id)
    assert FcmPusher.enabled_for?(user, ws), "workspace push on by default"

    ws.memberships.find_by(user_id: user.id).update!(push_enabled: false)
    assert_not FcmPusher.enabled_for?(user.reload, ws), "muted workspace gates the push"
  end

  test "send_alert is a no-op when the user muted this workspace" do
    user = users(:one)
    ws = Workspace.create!(name: "WS", slug: "fcm-#{SecureRandom.hex(4)}", owner_id: user.id)
    ws.memberships.find_by(user_id: user.id).update!(push_enabled: false)
    DeviceToken.create!(token: "and-ws", platform: "android", user: user)
    assert_nil FcmPusher.send_alert(note, user: user.reload, workspace: ws)
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

  test "delivered payload targets the high-importance fcm_default channel" do
    user = users(:one)
    user.update!(android_push_enabled: true)
    DeviceToken.create!(token: "and-ch", platform: "android", user: user)

    captured = nil
    ok = Net::HTTPOK.new("1.1", "200", "OK")
    # Stub the network + auth layer so nothing leaves the process; capture the
    # body FcmPusher would POST and assert it names the channel.
    FcmPusher.stub(:credentials, { "project_id" => "p" }) do
      FcmPusher.stub(:access_token, "tok") do
        FcmPusher.stub(:post_json, ->(_uri, body, _at) { captured = body; ok }) do
          FcmPusher.send_alert(note, user: user)
        end
      end
    end

    assert_equal "fcm_default", captured.dig(:message, :android, :notification, :channel_id)
    assert_equal "HIGH", captured.dig(:message, :android, :priority)
  end
end
