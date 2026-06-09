require "test_helper"

class KitchenMailerTest < ActionMailer::TestCase
  test "smoke_failure_report renders the error, console, and note" do
    run = SmokeTestRun.create!(name: "nyk_calendar_nav", status: "failed",
                               started_at: Time.zone.parse("2026-06-08 09:00"),
                               duration_ms: 31_000, error_message: "Rows 1 and 2 vanished on return",
                               console_errors: "TypeError: undefined is not a function")

    mail = KitchenMailer.smoke_failure_report(run, recipient: "dev@example.com",
                                              note: "Can you take a look?", from_name: "lora.downie@nykitchen.com")

    assert_equal [ "dev@example.com" ], mail.to
    assert_match "nyk_calendar_nav", mail.subject
    body = mail.html_part.body.to_s
    assert_match "Rows 1 and 2 vanished on return", body
    assert_match "TypeError", body
    assert_match "Can you take a look?", body
    assert_match "lora.downie@nykitchen.com", body
    # No artifacts attached, so no recording link.
    assert_match "No video or trace was captured", body
  end

  test "smoke_failure_report links the recording when a video is attached" do
    run = SmokeTestRun.create!(name: "nyk_calendar_nav", status: "failed",
                               started_at: Time.zone.parse("2026-06-08 09:00"),
                               error_message: "boom")
    run.video.attach(io: StringIO.new("fake-webm"), filename: "run.webm", content_type: "video/webm")

    mail = KitchenMailer.smoke_failure_report(run, recipient: "dev@example.com")
    body = mail.html_part.body.to_s
    assert_match "Screen recording", body
    assert_match "/rails/active_storage/", body
  end
end
