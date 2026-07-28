require "test_helper"
require "minitest/mock"

class TelegramNotifierTest < ActiveSupport::TestCase
  setup    { Setting.delete_key(TelegramNotifier::MUTE_KEY) }
  teardown { Setting.delete_key(TelegramNotifier::MUTE_KEY) }

  test "muted? reflects the Setting" do
    assert_not TelegramNotifier.muted?
    Setting.set(TelegramNotifier::MUTE_KEY, "true")
    assert TelegramNotifier.muted?
    Setting.set(TelegramNotifier::MUTE_KEY, "false")
    assert_not TelegramNotifier.muted?
  end

  test "send_alert opens no HTTP connection when muted, even if creds were present" do
    Setting.set(TelegramNotifier::MUTE_KEY, "true")
    note = Notification.new(level: "info", source: "test", title: "hi", body: "b")
    # The mute check runs before ENV/HTTP, so no connection should ever open.
    Net::HTTP.stub(:new, ->(*) { raise "TelegramNotifier must not POST when muted" }) do
      assert_nil TelegramNotifier.send_alert(note)
    end
  end

  test "no-op without creds when not muted (unchanged default behavior)" do
    note = Notification.new(level: "info", source: "test", title: "hi")
    # Test env has no TELEGRAM_* creds, so it should early-return quietly.
    assert_nil TelegramNotifier.send_alert(note)
  end
end
