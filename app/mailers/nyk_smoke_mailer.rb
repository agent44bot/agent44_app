class NykSmokeMailer < ApplicationMailer
  TARGET_URL = "https://nykitchen.com/calendar/"

  # Sent when the NY Kitchen calendar smoke test fails.
  # Recipients are explicit so this mailer can be invoked from anywhere
  # (test host, Rails console on prod, etc.) without autoloading the test class.
  def failure(failure_message:, video_path:, screenshot_path:, trace_path:, started_at:, recipients:)
    @failure_message = failure_message
    @video_path = video_path
    @screenshot_path = screenshot_path
    @trace_path = trace_path
    @started_at = started_at
    @target_url = TARGET_URL

    # No attachments: HEY (and many other mail clients) silently filter any
    # email with a video/image attachment to spam. The raw artifacts (video,
    # screenshot, trace.zip) are saved to tmp/smoke/ on the test host for
    # developer debugging; the recipient is pointed at agent44labs.com/kitchen
    # Tests tab to see the run record and the live NY Kitchen calendar.

    mail(
      to: recipients,
      subject: "NY Kitchen calendar smoke FAILED - arrow nav may be broken again"
    )
  end
end
