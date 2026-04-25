class NykSmokeMailer < ApplicationMailer
  TARGET_URL = "https://nykitchen.com/calendar/"
  TESTS_TAB_URL = "https://agent44labs.com/nykitchen?tab=tests"

  # Recipients hardcoded while we tune the alert format. Add back to the
  # GHA secret + remove this constant when ready to broaden distribution.
  CURRENT_RECIPIENTS = %w[botwhisperer@hey.com].freeze

  # Sent when the NY Kitchen calendar smoke test fails. The `recipients`
  # param is currently ignored — see CURRENT_RECIPIENTS above.
  def failure(failure_message:, video_path: nil, screenshot_path: nil, trace_path: nil, started_at:, recipients: nil, console_errors: nil)
    @failure_message = failure_message.to_s
    @console_errors = Array(console_errors).reject(&:blank?)
    @started_at = started_at
    @target_url = TARGET_URL
    @tests_tab_url = TESTS_TAB_URL

    mail(
      to: CURRENT_RECIPIENTS,
      subject: "🚨 NY Kitchen smoke failed — #{@started_at.strftime("%-I:%M %p %Z")}"
    )
  end
end
