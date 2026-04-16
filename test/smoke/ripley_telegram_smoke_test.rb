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

  # Homepage polls every 10s (agent_status_controller.js). Hold busy long enough
  # that at least one poll lands inside the window so the dot visibly flips amber.
  BUSY_DWELL_SECONDS = Integer(ENV["SMOKE_BUSY_DWELL"] || 12)

  test "Ripley busy/online transitions reach the live endpoint" do
    busy = HTTParty.patch("#{BASE}/api/v1/agents/Ripley/status",
      headers: @headers,
      body: { status: "busy", current_task: "Smoke: Ripley unmute verify" }.to_json)
    assert_equal 200, busy.code, "busy PATCH failed: #{busy.body}"
    assert_equal "busy", busy.parsed_response["status"]

    puts "\n  🟡 Ripley busy — holding #{BUSY_DWELL_SECONDS}s so the homepage dot flips amber..."
    sleep BUSY_DWELL_SECONDS

    online = HTTParty.patch("#{BASE}/api/v1/agents/Ripley/status",
      headers: @headers,
      body: { status: "online", current_task: nil }.to_json)
    assert_equal 200, online.code, "online PATCH failed: #{online.body}"
    assert_equal "online", online.parsed_response["status"]

    puts "  ✉️  Check Telegram: expect 'Ripley is now working' then 'Ripley finished task'"
    puts "  🟢 Check agent44labs.com: Ripley's dot should have turned amber then back to green"
  end
end
