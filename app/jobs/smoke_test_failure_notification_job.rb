class SmokeTestFailureNotificationJob < ApplicationJob
  queue_as :default

  # Called after a smoke test run fails
  # Sends iOS push notifications to:
  #   - All admin users
  #   - All kitchen_customer users (if it's a NY Kitchen test)
  def perform(smoke_test_run_id)
    run = SmokeTestRun.find_by(id: smoke_test_run_id)
    return unless run&.failed?

    notify_admins!(run)
    notify_kitchen_users!(run) if nyk_test?(run)
  end

  private

  def notify_admins!(run)
    User.where(role: "admin").find_each do |user|
      send_ios_notification(user, run)
    end
  end

  def notify_kitchen_users!(run)
    User.where(role: "kitchen_customer").find_each do |user|
      send_ios_notification(user, run)
    end
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

  def nyk_test?(run)
    run.name.to_s.start_with?("nyk_")
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
