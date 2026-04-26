class NykSmokeMailer < ApplicationMailer
  TARGET_URL = "https://nykitchen.com/calendar/"
  TESTS_TAB_URL = "https://agent44labs.com/nykitchen?tab=tests"

  def failure(failure_message:, video_path: nil, screenshot_path: nil, trace_path: nil, started_at:, recipients:, console_errors: nil)
    @failure_message = failure_message.to_s
    @console_errors = Array(console_errors).reject(&:blank?)
    @started_at = started_at
    @target_url = TARGET_URL
    @tests_tab_url = TESTS_TAB_URL

    mail(
      to: recipients,
      subject: "🚨 NY Kitchen smoke failed — #{@started_at.strftime("%-I:%M %p %Z")}"
    )
  end
end
