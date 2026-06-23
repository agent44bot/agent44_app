require "test_helper"
require "minitest/mock"

class NotificationTest < ActiveSupport::TestCase
  test "notify! with apns: true fans out to both iOS (APNs) and Android (FCM)" do
    user = users(:one)
    called = []
    ApnsPusher.stub(:send_alert, ->(*_a, **_k) { called << :apns }) do
      FcmPusher.stub(:send_alert, ->(*_a, **_k) { called << :fcm }) do
        Notification.notify!(level: "info", source: "test", title: "T", apns: true, apns_user: user)
      end
    end
    assert_equal %i[apns fcm], called
  end

  test "notify! without apns does not push to either platform" do
    called = []
    ApnsPusher.stub(:send_alert, ->(*_a, **_k) { called << :apns }) do
      FcmPusher.stub(:send_alert, ->(*_a, **_k) { called << :fcm }) do
        Notification.notify!(level: "info", source: "test", title: "T")
      end
    end
    assert_empty called
  end

  test "notify! forwards workspace to both pushers for per-workspace gating" do
    user = users(:one)
    ws = Workspace.create!(name: "WS", slug: "ntf-#{SecureRandom.hex(4)}", owner_id: user.id)
    seen = []
    ApnsPusher.stub(:send_alert, ->(*_a, **k) { seen << k[:workspace] }) do
      FcmPusher.stub(:send_alert, ->(*_a, **k) { seen << k[:workspace] }) do
        Notification.notify!(level: "info", source: "test", title: "T",
                             apns: true, apns_user: user, workspace: ws)
      end
    end
    assert_equal [ ws, ws ], seen
  end
end
