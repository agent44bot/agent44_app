require "test_helper"

# Multi-tenant slice 1: kitchen data is scoped per workspace. The snapshot API
# is the first entry point that takes an explicit workspace_slug; the web
# routes still default to NY Kitchen until slice 2 mounts them per slug.
class KitchenTenantTest < ActionDispatch::IntegrationTest
  setup do
    @token = "test-api-token-#{SecureRandom.hex(8)}"
    ENV["API_TOKEN"] = @token
    @headers = { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" }
    @nyk = nyk_workspace!
    owner = User.create!(email_address: "flci-#{SecureRandom.hex(3)}@example.com")
    @other = Workspace.create!(name: "FLX Culinary", slug: "flxculinary", owner: owner, kitchen_enabled: true)
    @today = Date.current.to_s
  end

  teardown { ENV.delete("API_TOKEN") }

  def post_snapshot(slug: nil, url:)
    params = { taken_on: @today, events: [ { url: url, name: "Class", start_at: 2.days.from_now.iso8601,
                                             spots_left: 5, capacity: 10, availability: "InStock" } ] }
    params[:workspace_slug] = slug if slug
    post "/api/v1/kitchen_snapshots", params: params.to_json, headers: @headers
  end

  test "two kitchen workspaces can each snapshot the same day" do
    post_snapshot(url: "https://nykitchen.com/e/1")
    assert_response :created
    post_snapshot(slug: "flxculinary", url: "https://flx.example/e/1")
    assert_response :created

    assert_equal 1, @nyk.kitchen_snapshots.count
    assert_equal 1, @other.kitchen_snapshots.count
    assert_equal [ "https://nykitchen.com/e/1" ], @nyk.kitchen_snapshots.latest.kitchen_events.pluck(:url)
    assert_equal [ "https://flx.example/e/1" ], @other.kitchen_snapshots.latest.kitchen_events.pluck(:url)
  end

  test "no workspace_slug means NY Kitchen" do
    post_snapshot(url: "https://nykitchen.com/e/2")
    assert_equal @nyk, KitchenSnapshot.last.workspace
  end

  test "an unknown or non-kitchen slug is 404, never NYK's data" do
    Workspace.create!(name: "Plain", slug: "plain", owner: @other.owner)
    post_snapshot(slug: "plain", url: "https://x.example/e")
    assert_response :not_found
    post_snapshot(slug: "nope", url: "https://x.example/e")
    assert_response :not_found
    assert_equal 0, @nyk.kitchen_snapshots.count
  end

  test "GET upcoming with a bad slug is a JSON 404 too" do
    get "/api/v1/kitchen_snapshots/upcoming", params: { workspace_slug: "nope" }, headers: @headers
    assert_response :not_found
    assert_equal "application/json", response.media_type
  end

  test "kitchen records created without a workspace default into NY Kitchen (transitional)" do
    snap = KitchenSnapshot.create!(taken_on: Date.current)
    assert_equal @nyk, snap.workspace
    run = SmokeTestRun.create!(name: "nyk_calendar_nav", status: "passed", started_at: Time.current, duration_ms: 60_000)
    assert_equal @nyk, run.workspace
  end

  test "smoke run cost uses the run's own workspace rate" do
    @other.update!(test_cost_per_minute: 0.01)
    run = @other.smoke_test_runs.create!(name: "nyk_calendar_nav", status: "passed", started_at: Time.current, duration_ms: 60_000)
    assert_in_delta 0.01, run.cost_dollars, 1e-6
  end

  test "the web routes still resolve to NY Kitchen without a slug" do
    get "/nykitchen/display"
    assert_response :success
  end
end
