# frozen_string_literal: true

# Asks GitHub Actions to run part of the NY Kitchen Playwright suite on the Mac
# mini runner.
#
# This is the only way the app can cause a scrape. SiteGround CAPTCHAs Fly's IP,
# so anything that scrapes from the app server comes back empty; the mini runs
# from a residential IP and POSTs its results to /api/v1/kitchen_snapshots.
#
# `test:` maps to the workflow's own choices (nav, scrape, print, all) and rides
# along as client_payload, which smoke-nyk.yml reads to pick the files to run.
class SmokeDispatch
  EVENT_TYPE   = "smoke-nyk"
  DISPATCH_URL = "https://api.github.com/repos/agent44bot/agent44_app/dispatches"

  TESTS = %w[all nav nav_mobile scrape print].freeze

  # Returns :ok, :no_token, or :failed.
  def self.trigger!(requested_by:, via:, test: nil)
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
    payload = { event_type: EVENT_TYPE }
    payload[:client_payload] = { test: test } if TESTS.include?(test.to_s)
    req.body = payload.to_json

    res = http.request(req)

    if res.is_a?(Net::HTTPSuccess) || res.code == "204"
      Notification.notify!(
        level:    "info",
        source:   "smoke_test",
        title:    "Smoke test triggered",
        body:     "#{requested_by} requested NY Kitchen #{test.presence || 'smoke'} run via #{via}",
        telegram: true
      )
      Rails.logger.info("[smoke_dispatch] #{test.presence || 'all'} triggered by #{requested_by} via #{via}")
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
