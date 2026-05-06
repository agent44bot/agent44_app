require "apnotic"

class ApnsPusher
  def self.send_alert(notification, url: nil, subtitle: nil, user: nil)
    scope = DeviceToken.active.ios
    scope = scope.for_user(user) if user
    tokens = scope.pluck(:token)
    return if tokens.empty?

    badge = user ? user.notifications.unread.count : nil

    connection = build_connection
    return unless connection

    tokens.each do |token|
      push_notification = Apnotic::Notification.new(token)
      alert = { title: notification.title, body: notification.body || "" }
      alert[:subtitle] = subtitle if subtitle
      push_notification.alert = alert
      push_notification.sound = "default"
      push_notification.topic = "com.agent44labs.app"
      push_notification.badge = badge if badge
      push_notification.custom_payload = { url: url } if url

      response = connection.push(push_notification)
      handle_response(response, token)
    end
  ensure
    connection&.close
  end

  # Sends a silent (content-available) push to the user's iOS devices that
  # zeroes the app icon badge. Used after the user opens the app.
  def self.clear_badge_for(user)
    tokens = DeviceToken.active.ios.for_user(user).pluck(:token)
    return if tokens.empty?

    connection = build_connection
    return unless connection

    tokens.each do |token|
      push_notification = Apnotic::Notification.new(token)
      push_notification.topic = "com.agent44labs.app"
      push_notification.content_available = 1
      push_notification.badge = 0

      response = connection.push(push_notification)
      handle_response(response, token)
    end
  ensure
    connection&.close
  end

  def self.build_connection
    key_content = ENV["APNS_AUTH_KEY"] || Rails.application.credentials.dig(:apns, :auth_key)
    key_id      = ENV["APNS_KEY_ID"]  || Rails.application.credentials.dig(:apns, :key_id)
    team_id     = ENV["APNS_TEAM_ID"] || Rails.application.credentials.dig(:apns, :team_id)

    unless key_content.present? && key_id.present? && team_id.present?
      Rails.logger.warn("ApnsPusher: missing APNs credentials, skipping push")
      return nil
    end

    Apnotic::Connection.new(
      auth_method: :token,
      cert_path: StringIO.new(key_content),
      key_id: key_id,
      team_id: team_id
    )
  rescue => e
    Rails.logger.error("ApnsPusher connection error: #{e.message}")
    nil
  end

  def self.handle_response(response, token)
    unless response
      Rails.logger.warn("ApnsPusher: no response for token #{token[0..8]}...")
      return
    end

    if response.status == "410" || (response.status != "200" && response.body&.dig("reason") == "Unregistered")
      DeviceToken.where(token: token).update_all(active: false)
      Rails.logger.info("ApnsPusher: deactivated stale token #{token[0..8]}...")
    elsif response.status != "200"
      Rails.logger.warn("ApnsPusher: failed for #{token[0..8]}... (#{response.status}): #{response.body}")
    end
  end

  private_class_method :build_connection, :handle_response
end
