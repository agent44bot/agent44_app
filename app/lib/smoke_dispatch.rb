# frozen_string_literal: true

# Kicks off the NY Kitchen smoke test by asking GitHub Actions to run it
# (the test itself is Playwright, driven by a workflow, not an in-app job).
#
# Extracted from the Telegram webhook so the Buzz listener triggers it the exact
# same way rather than growing a second copy of the dispatch call.
class SmokeDispatch
  EVENT_TYPE   = "smoke-nyk"
  DISPATCH_URL = "https://api.github.com/repos/agent44bot/agent44_app/dispatches"

  # Returns :ok, :no_token, or :failed.
  def self.trigger!(requested_by:, via:)
    token = ENV["GITHUB_PAT"]
    if token.blank?
      Rails.logger.warn("[smoke_dispatch] GITHUB_PAT not set, cannot trigger smoke workflow")
      return :no_token
    end

    uri  = URI(DISPATCH_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.open_timeout = 5
    http.read_timeout = 10

    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{token}"
    req["Accept"]        = "application/vnd.github+json"
    req["Content-Type"]  = "application/json"
    req.body             = { event_type: EVENT_TYPE }.to_json

    res = http.request(req)

    if res.is_a?(Net::HTTPSuccess) || res.code == "204"
      Notification.notify!(
        level:    "info",
        source:   "smoke_test",
        title:    "Smoke test triggered",
        body:     "#{requested_by} requested NY Kitchen smoke test via #{via}",
        telegram: true
      )
      Rails.logger.info("[smoke_dispatch] triggered by #{requested_by} via #{via}")
      :ok
    else
      Rails.logger.error("[smoke_dispatch] GitHub dispatch failed (#{res.code}): #{res.body.to_s[0, 200]}")
      :failed
    end
  rescue StandardError => e
    Rails.logger.error("[smoke_dispatch] error: #{e.class}: #{e.message}")
    :failed
  end
end
