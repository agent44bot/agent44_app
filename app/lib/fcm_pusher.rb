require "net/http"
require "json"
require "openssl"
require "base64"

# Android push via Firebase Cloud Messaging (HTTP v1), the Android counterpart
# to ApnsPusher. Auth is a Google service account: we sign a short-lived JWT
# with the account's private key, exchange it for an OAuth access token (cached
# ~55 min), and POST one message per device token.
#
# Credentials (either env or Rails credentials):
#   FCM_SERVICE_ACCOUNT_JSON  - the full service-account JSON (string)
#   FCM_PROJECT_ID            - optional; falls back to project_id in the JSON
# When credentials are absent (e.g. local/dev/test) every call is a safe no-op.
class FcmPusher
  SCOPE     = "https://www.googleapis.com/auth/firebase.messaging".freeze
  TOKEN_URI = "https://oauth2.googleapis.com/token".freeze
  ACCESS_TOKEN_CACHE_KEY = "fcm:access_token".freeze

  def self.send_alert(notification, url: nil, subtitle: nil, user: nil, workspace: nil)
    return unless enabled_for?(user, workspace)

    scope = DeviceToken.active.android
    scope = scope.for_user(user) if user
    tokens = scope.pluck(:token)
    return if tokens.empty?

    creds = credentials
    return unless creds

    token = access_token(creds)
    return unless token

    tokens.each { |t| deliver(creds, token, t, notification, url, subtitle) }
  rescue => e
    Rails.logger.error("FcmPusher error: #{e.message}")
    nil
  end

  # A user with Android push turned off (or no user = broadcast) gates here, as
  # does a user who muted push for this notification's workspace.
  def self.enabled_for?(user, workspace = nil)
    user.nil? || (user.android_push_enabled && user.push_enabled_for_workspace?(workspace))
  end

  def self.credentials
    raw = ENV["FCM_SERVICE_ACCOUNT_JSON"] || Rails.application.credentials.dig(:fcm, :service_account_json)
    return nil if raw.blank?

    json = raw.is_a?(String) ? JSON.parse(raw) : raw.to_h.transform_keys(&:to_s)
    project_id = ENV["FCM_PROJECT_ID"].presence || json["project_id"]
    unless json["client_email"].present? && json["private_key"].present? && project_id.present?
      Rails.logger.warn("FcmPusher: incomplete FCM service-account credentials, skipping push")
      return nil
    end
    json.merge("project_id" => project_id)
  rescue JSON::ParserError => e
    Rails.logger.error("FcmPusher: bad FCM_SERVICE_ACCOUNT_JSON (#{e.message})")
    nil
  end

  # OAuth access token from the service account, cached just under its 1h TTL.
  def self.access_token(creds)
    Rails.cache.fetch(ACCESS_TOKEN_CACHE_KEY, expires_in: 55.minutes) do
      assertion = signed_jwt(creds)
      res = post_form(TOKEN_URI, {
        "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion"  => assertion
      })
      unless res.is_a?(Net::HTTPSuccess)
        Rails.logger.error("FcmPusher: token exchange failed (#{res.code}): #{res.body}")
        next nil
      end
      JSON.parse(res.body)["access_token"]
    end
  end

  # Build + RS256-sign the service-account JWT with stdlib OpenSSL (no gem).
  def self.signed_jwt(creds)
    now = Time.now.to_i
    header  = { alg: "RS256", typ: "JWT" }
    payload = {
      iss: creds["client_email"], scope: SCOPE, aud: TOKEN_URI,
      iat: now, exp: now + 3600
    }
    signing_input = [ b64(header.to_json), b64(payload.to_json) ].join(".")
    key = OpenSSL::PKey::RSA.new(creds["private_key"])
    signature = key.sign(OpenSSL::Digest.new("SHA256"), signing_input)
    "#{signing_input}.#{b64(signature)}"
  end

  def self.deliver(creds, access_token, device_token, notification, url, subtitle)
    body = {
      message: {
        token: device_token,
        notification: { title: notification.title, body: notification.body.to_s },
        data: url ? { url: url.to_s } : {},
        android: { priority: "HIGH", notification: { sound: "default" } }
      }
    }
    body[:message][:notification][:subtitle] = subtitle if subtitle

    uri = URI("https://fcm.googleapis.com/v1/projects/#{creds['project_id']}/messages:send")
    res = post_json(uri, body, access_token)
    handle_response(res, device_token)
  end

  def self.handle_response(res, token)
    return if res.is_a?(Net::HTTPSuccess)

    # 404 / UNREGISTERED => the app was uninstalled or the token rotated.
    reason = (JSON.parse(res.body)["error"] rescue {})["status"]
    if res.code == "404" || reason == "UNREGISTERED" || reason == "NOT_FOUND"
      DeviceToken.where(token: token).update_all(active: false)
      Rails.logger.info("FcmPusher: deactivated stale token #{token[0, 9]}...")
    else
      Rails.logger.warn("FcmPusher: failed for #{token[0, 9]}... (#{res.code}): #{res.body}")
    end
  end

  def self.post_form(url, form)
    uri = URI(url)
    req = Net::HTTP::Post.new(uri)
    req.set_form_data(form)
    http_request(uri, req)
  end

  def self.post_json(uri, body, access_token)
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{access_token}"
    req["Content-Type"] = "application/json"
    req.body = body.to_json
    http_request(uri, req)
  end

  def self.http_request(uri, req)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.request(req)
    end
  end

  def self.b64(str)
    Base64.urlsafe_encode64(str, padding: false)
  end

  private_class_method :credentials, :access_token, :signed_jwt, :deliver,
                       :handle_response, :post_form, :post_json, :http_request, :b64
end
