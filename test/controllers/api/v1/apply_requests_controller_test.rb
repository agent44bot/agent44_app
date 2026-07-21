require "test_helper"

class Api::V1::ApplyRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = "test-token-#{SecureRandom.hex(8)}"
    ENV["API_TOKEN"] = @token
    @headers = { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" }
    @job = Job.create!(title: "Ruby SDET", company: "Acme", url: "https://example.com/#{SecureRandom.hex(5)}",
                       source: "test", category: "contract", location: "Remote", active: true)
    @req = ApplyRequest.enqueue!(@job)
  end

  teardown { ENV.delete("API_TOKEN") }

  test "index requires the API token" do
    get "/api/v1/apply_requests"
    assert_response :unauthorized
  end

  test "index returns pending requests with the application profile" do
    get "/api/v1/apply_requests", headers: @headers
    assert_response :success
    body = JSON.parse(response.body)
    assert body["profile"].is_a?(Hash), "should include the application profile to fill forms with"
    row = body["requests"].find { |r| r["id"] == @req.id }
    assert row, "queued request should be listed"
    assert_equal "queued", row["status"]
    assert_equal @job.url, row.dig("job", "url")
  end

  test "update advances status and stamps the lifecycle timestamp" do
    patch "/api/v1/apply_requests/#{@req.id}",
          params: { status: "filled", notes: "opened Greenhouse, filled fields, stopped at submit" }.to_json,
          headers: @headers
    assert_response :success
    @req.reload
    assert_equal "filled", @req.status
    assert_equal "opened Greenhouse, filled fields, stopped at submit", @req.notes
    assert @req.filled_at.present?
  end

  test "update rejects an invalid status" do
    patch "/api/v1/apply_requests/#{@req.id}", params: { status: "bogus" }.to_json, headers: @headers
    assert_response :unprocessable_entity
  end

  test "update requires the API token" do
    patch "/api/v1/apply_requests/#{@req.id}", params: { status: "opened" }.to_json
    assert_response :unauthorized
  end
end
