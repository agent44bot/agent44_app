# Pushes to Rich about a Feedback item (submitted, plan ready, ready to merge,
# stuck, live). Each one deep-links to the item's admin page, where the
# buttons for that step are. Telegram rides along unless muted app-wide.
module FeedbackAlerts
  ALERT_EMAIL_KEY = "feedback.alert_email".freeze

  def self.push(feedback, title, body = nil, level: "info")
    Notification.notify!(
      level: level,
      source: "feedback",
      title: title,
      body: body.to_s.squish.truncate(300).presence,
      telegram: true,
      apns: true,
      apns_user: alert_user,
      apns_url: "/admin/feedbacks/#{feedback.id}"
    )
  end

  # Settings "feedback.alert_email" when set, else the first admin (Rich).
  def self.alert_user
    email = Setting.get(ALERT_EMAIL_KEY).to_s.strip
    (email.present? && User.find_by(email_address: email)) ||
      User.where(role: "admin").order(:id).first
  end
end
