class SmokeTestFailureNotificationJob < ApplicationJob
  queue_as :default

  # Called after a smoke test run fails. Sends iOS push notifications to
  # all admins, plus members of the workspace the test belongs to
  # (today: ny-kitchen for any nyk_* run).
  def perform(smoke_test_run_id)
    run = SmokeTestRun.find_by(id: smoke_test_run_id)
    return unless run&.failed?

    notified_ids = Set.new
    User.where(role: "admin").find_each do |user|
      send_ios_notification(user, run)
      notified_ids << user.id
    end

    workspace_for(run)&.users&.where&.not(id: notified_ids)&.find_each do |user|
      send_ios_notification(user, run)
    end
  end

  private

  def workspace_for(run)
    return Workspace.find_by(slug: "ny-kitchen") if run.name.to_s.start_with?("nyk_")
    nil
  end

  def send_ios_notification(user, run)
    title = "NY Kitchen test failed"
    subtitle = run.kind.capitalize
    body = truncate_body(run.summary, run.error_message)
    url = "/smoke_runs/#{run.id}"

    Notification.notify!(
      level:        "error",
      source:       "smoke_test_failure",
      title:        title,
      body:         body,
      apns:         true,
      apns_url:     url,
      apns_subtitle: subtitle,
      apns_user:    user
    )
  rescue => e
    Rails.logger.error("SmokeTestFailureNotificationJob failed for user #{user.id}, run #{run.id}: #{e.message}")
  end

  def truncate_body(summary, error_message)
    body = summary.to_s.presence || ""
    if error_message.present?
      body = "#{body}\n#{error_message}" if body.present?
      body = error_message if body.blank?
    end
    body.truncate(200)
  end
end
