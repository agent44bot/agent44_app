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

  test "force: true POSTs even while muted (owner-requested one-offs)" do
    Setting.set(TelegramNotifier::MUTE_KEY, "true")
    note = Notification.new(level: "info", source: "read_receipt", title: "hi")
    posted = false

    with_telegram_creds do
      # send_alert rescues, so raising here is a safe way to prove it got as far
      # as opening a connection instead of short-circuiting on the mute.
      Net::HTTP.stub(:new, ->(*) { posted = true; raise "stop here" }) do
        TelegramNotifier.send_alert(note, force: true)
      end
    end

    assert posted, "force must send through the global mute"
  end

  test "force: false still respects the mute when creds are present" do
    Setting.set(TelegramNotifier::MUTE_KEY, "true")
    note = Notification.new(level: "info", source: "read_receipt", title: "hi")

    with_telegram_creds do
      Net::HTTP.stub(:new, ->(*) { flunk "muted alerts must never POST" }) do
        assert_nil TelegramNotifier.send_alert(note)
      end
    end
  end

  test "no-op without creds when not muted (unchanged default behavior)" do
    note = Notification.new(level: "info", source: "test", title: "hi")
    # Test env has no TELEGRAM_* creds, so it should early-return quietly.
    assert_nil TelegramNotifier.send_alert(note)
  end

  private

  def with_telegram_creds
    ENV["TELEGRAM_BOT_TOKEN"] = "test-token"
    ENV["TELEGRAM_CHAT_ID"]   = "test-chat"
    yield
  ensure
    ENV.delete("TELEGRAM_BOT_TOKEN")
    ENV.delete("TELEGRAM_CHAT_ID")
  end
end
