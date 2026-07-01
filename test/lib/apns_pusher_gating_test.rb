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

  test "enabled_for? is false when the user muted this workspace (iOS)" do
    user = users(:one)
    user.update!(ios_push_enabled: true)
    owner = User.create!(email_address: "apns-ws-#{SecureRandom.hex(4)}@example.com")
    ws = Workspace.create!(name: "APNs WS", owner: owner)
    m  = ws.memberships.create!(user: user, role: "editor")

    assert ApnsPusher.enabled_for?(user, ws), "member with push on gets it"
    m.update!(push_enabled: false)
    assert_not ApnsPusher.enabled_for?(user, ws), "muting the workspace blocks iOS too"
  end
end
