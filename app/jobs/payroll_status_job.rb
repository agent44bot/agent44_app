class PayrollStatusJob < ApplicationJob
  queue_as :default

  # Payroll status nudge for Lora's Wednesday 4pm payroll deadline. Emails and
  # iOS-pushes Rich + Lora the approval status of the pay week's Deputy
  # timesheets, so Lora knows what still needs approving before she submits.
  #
  # Scheduled Mon/Tue/Wed at 10:05am ET (config/recurring.yml), just after the
  # 10am class digest, and deliberately SEPARATE from that digest. Telegram is
  # muted app-wide, so this rides email + iOS push only.
  RECIPIENTS = [ "botwhisperer@hey.com", "lora.downie@nykitchen.com" ].freeze

  def perform
    return unless DeputyClient.configured?

    # The pay week Wednesday's payroll covers = the most recent COMPLETE Mon-Sun
    # (the week that ended this past Sunday). On Mon/Tue/Wed that's "last week".
    week_start = Date.current.beginning_of_week(:monday) - 7
    week_end   = week_start + 6

    status =
      begin
        DeputyClient.timesheet_status(week_start, week_end)
      rescue DeputyClient::Error => e
        Rails.logger.warn("PayrollStatusJob: Deputy fetch failed: #{e.message}")
        return
      end

    deadline = deadline_phrase
    level    = status[:total].positive? && status[:pending].zero? ? "success" : "warning"
    body     = push_summary(status, deadline)
    ws       = Workspace.find_by(slug: "nykitchen")

    # iOS push to Rich + Lora only (each gets their own record so the app badge
    # tracks their unread count). Tapping opens the Team hours page.
    User.where(email_address: RECIPIENTS).find_each do |user|
      Notification.notify!(
        level: level, source: "payroll_status", title: "Payroll status", body: body,
        apns: true, apns_url: "/nykitchen/hours", apns_user: user, workspace: ws
      )
    end

    KitchenMailer.payroll_status(
      recipients: RECIPIENTS, week_start: week_start, week_end: week_end,
      status: status, deputy_url: DeputyClient.approve_url, deadline: deadline
    ).deliver_later
  end

  private

  # Human phrase for the Wednesday 4pm deadline. The job runs only Mon/Tue/Wed,
  # so wday is 1, 2, or 3.
  def deadline_phrase
    case Date.current.wday
    when 3 then "today at 4pm"                # Wednesday
    when 2 then "tomorrow (Wednesday) at 4pm" # Tuesday
    else        "Wednesday at 4pm"            # Monday
    end
  end

  def push_summary(status, deadline)
    if status[:total].zero?
      "No timesheets generated yet for the pay week. Payroll due #{deadline}. Tap to generate."
    elsif status[:pending].zero?
      "All #{status[:total]} timesheets approved. Ready for payroll #{deadline}."
    else
      "#{status[:approved]} of #{status[:total]} approved, #{status[:pending]} still pending. Payroll due #{deadline}."
    end
  end
end
