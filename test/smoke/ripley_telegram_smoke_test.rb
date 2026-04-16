require "test_helper"
require "httparty"

# Out-of-process smoke test that hits the *live* deployment and sends real
# Telegram pings. Skipped by default so CI never fires this. Run explicitly:
#
#   RUN_SMOKE=true API_TOKEN=xxx bin/rails test test/smoke/
#
# Override the target with SMOKE_BASE_URL=https://staging... if needed.
class RipleyTelegramSmokeTest < ActiveSupport::TestCase
  BASE = ENV["SMOKE_BASE_URL"] || "https://agent44-app.fly.dev"

  def self.runnable_methods
    ENV["RUN_SMOKE"] == "true" ? super : []
  end

  setup do
    @token = ENV["API_TOKEN"] || Rails.application.credentials.api_token
    raise "No API_TOKEN (set env var or Rails credentials api_token)" unless @token
    @headers = {
      "Authorization" => "Bearer #{@token}",
      "Content-Type"  => "application/json"
    }
  end

  test "Ripley busy/online transitions reach the live endpoint" do
    busy = HTTParty.patch("#{BASE}/api/v1/agents/Ripley/status",
      headers: @headers,
      body: { status: "busy", current_task: "Smoke: Ripley unmute verify" }.to_json)
    assert_equal 200, busy.code, "busy PATCH failed: #{busy.body}"
    assert_equal "busy", busy.parsed_response["status"]

    sleep 1

    online = HTTParty.patch("#{BASE}/api/v1/agents/Ripley/status",
      headers: @headers,
      body: { status: "online", current_task: nil }.to_json)
    assert_equal 200, online.code, "online PATCH failed: #{online.body}"
    assert_equal "online", online.parsed_response["status"]

    puts "\n  ✉️  Check Telegram: expect 'Ripley is now working' then 'Ripley finished task'"
  end
end
