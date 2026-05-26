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

    maybe_escalate_streak(run)
  end

  private

  # On top of the per-run push above, send ONE higher-signal "failing
  # repeatedly" alert to the trial user when the nav streak crosses the
  # threshold — deep-linked to the Super Agent so a tap auto-asks it to triage
  # and draft a note to the developer. De-duped per incident so it fires once,
  # not on every subsequent failure or job retry.
  def maybe_escalate_streak(run)
    return unless run.kind == "nav" # only the customer-facing calendar check escalates
    return unless KitchenAi::SmokeEscalation.alerting?

    incident = KitchenAi::SmokeEscalation.incident_key
    return if incident.blank?
    return if Setting.get("smoke_streak_incident") == incident # already alerted this incident

    user = KitchenAi::SmokeEscalation.trial_user
    return unless user

    n      = KitchenAi::SmokeEscalation.streak
    prompt = KitchenAi::SmokeEscalation.draft_prompt(n)
    url    = "/nykitchen/ask?#{{ q: prompt, go: 1 }.to_query}"

    Notification.notify!(
      level:     "error",
      source:    "smoke_streak_escalation",
      title:     "NY Kitchen check failing repeatedly",
      body:      "The class calendar check has failed #{n} times in a row. Open Super Agent to draft a note to the developer?",
      apns:      true,
      apns_url:  url,
      apns_user: user
    )
    Setting.set("smoke_streak_incident", incident)
  end

  def workspace_for(run)
    return Workspace.find_by(slug: "nykitchen") if run.name.to_s.start_with?("nyk_")
    nil
  end

  def send_ios_notification(user, run)
    title = "NY Kitchen test failed"
    subtitle = run.kind.capitalize
    body = truncate_body(run.summary, run.error_message)
    # Test Agent hub on the NYK workspace — closest page that lists recent
    # smoke runs with their failure summaries. There is no per-run detail
    # page yet (the old /smoke_runs/:id deep link was a 404).
    url = "/nykitchen/test"

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
