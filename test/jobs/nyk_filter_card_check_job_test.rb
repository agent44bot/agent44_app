require "test_helper"

class NykFilterCardCheckJobTest < ActiveJob::TestCase
  setup do
    Setting.delete_all
  end

  test "first run seeds shipped_at and does nothing else" do
    NykFilterCardCheckJob.perform_now
    assert Setting.time("nyk.filter_card_shipped_at"), "shipped_at should be set"
    assert_nil Setting.time("nyk.filter_card_hidden_at")
  end

  test "does not hide before threshold" do
    Setting.set("nyk.filter_card_shipped_at", 5.days.ago.iso8601)
    NykFilterCardCheckJob.perform_now
    assert_nil Setting.time("nyk.filter_card_hidden_at")
  end

  test "hides + notifies after threshold with no expansion" do
    Setting.set("nyk.filter_card_shipped_at", 20.days.ago.iso8601)

    assert_difference -> { Notification.count }, 1 do
      NykFilterCardCheckJob.perform_now
    end

    assert Setting.time("nyk.filter_card_hidden_at"), "hidden_at should be set"
    note = Notification.order(:created_at).last
    assert_equal "nyk_ui", note.source
    assert_match(/auto-hidden/i, note.title)
  end

  test "does not hide if user expanded recently" do
    Setting.set("nyk.filter_card_shipped_at", 20.days.ago.iso8601)
    Setting.set("nyk.filter_card_last_expanded_at", 2.days.ago.iso8601)

    assert_no_difference -> { Notification.count } do
      NykFilterCardCheckJob.perform_now
    end
    assert_nil Setting.time("nyk.filter_card_hidden_at")
  end

  test "hides if last expansion is older than threshold" do
    Setting.set("nyk.filter_card_shipped_at", 30.days.ago.iso8601)
    Setting.set("nyk.filter_card_last_expanded_at", 20.days.ago.iso8601)

    NykFilterCardCheckJob.perform_now

    assert Setting.time("nyk.filter_card_hidden_at")
  end

  test "no-op if already hidden" do
    Setting.set("nyk.filter_card_shipped_at", 30.days.ago.iso8601)
    Setting.set("nyk.filter_card_hidden_at", 1.day.ago.iso8601)

    assert_no_difference -> { Notification.count } do
      NykFilterCardCheckJob.perform_now
    end
  end
end
