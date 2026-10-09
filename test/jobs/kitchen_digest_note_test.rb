require "test_helper"

class KitchenDigestNoteTest < ActiveSupport::TestCase
  test "note_for returns the note only on its date" do
    Setting.set("nyk_digest:note", "Congrats team")
    Setting.set("nyk_digest:note_on", "2026-10-09")

    assert_equal "Congrats team", KitchenDigestEmailJob.note_for(Date.new(2026, 10, 9))
    assert_nil KitchenDigestEmailJob.note_for(Date.new(2026, 10, 10))
  end

  test "note_for is nil when unset" do
    Setting.delete_key("nyk_digest:note")
    Setting.delete_key("nyk_digest:note_on")

    assert_nil KitchenDigestEmailJob.note_for(Date.new(2026, 10, 9))
  end

  test "daily digest renders the note, escaped" do
    digest = {
      today: Date.new(2026, 10, 9), current_week_events: [], week1_events: [], week2_events: [],
      week3_events: [], newly_sold_out: [], newly_added: [], removed: [], price_changes: [],
      total_upcoming: 0, total_sold_out: 0, snapshot_date: Date.new(2026, 10, 9), stale_data: false
    }
    html = KitchenMailer.daily_digest(digest, recipients: [ "a@example.com" ], note: "Great job <b>team</b>\n\nRich").body.encoded

    assert_includes html, "A note from (human) Rich"
    assert_includes html, "Great job &lt;b&gt;team&lt;/b&gt;"

    without = KitchenMailer.daily_digest(digest, recipients: [ "a@example.com" ]).body.encoded
    assert_not_includes without, "A note from (human) Rich"
  end
end
