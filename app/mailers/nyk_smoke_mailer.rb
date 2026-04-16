class NykSmokeMailer < ApplicationMailer
  # Sent when the NY Kitchen calendar smoke test fails.
  # Recipients placeholder — not delivered until explicitly flipped in the test.
  def failure(failure_message:, video_path:, screenshot_path:, trace_path:, started_at:, recipients:)
    @failure_message = failure_message
    @video_path = video_path
    @screenshot_path = screenshot_path
    @trace_path = trace_path
    @started_at = started_at
    @target_url = NykCalendarNavTest::TARGET_URL

    attachments["failure.webm"] = File.read(video_path) if video_path && File.exist?(video_path)
    attachments["failure.png"]  = File.read(screenshot_path) if screenshot_path && File.exist?(screenshot_path)
    attachments["trace.zip"]    = File.read(trace_path) if trace_path && File.exist?(trace_path)

    mail(
      to: recipients,
      subject: "🚨 NY Kitchen calendar smoke FAILED — arrow nav may be broken again"
    )
  end
end
