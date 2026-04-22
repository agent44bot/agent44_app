require "test_helper"

class Api::V1::DeviceTokensControllerTest < ActionDispatch::IntegrationTest
  test "POST create registers a new device token" do
    assert_difference "DeviceToken.count", 1 do
      post "/api/v1/device_tokens",
        params: { token: "abc123hextoken", platform: "ios" }.to_json,
        headers: { "Content-Type" => "application/json" }
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "abc123hextoken", body["token"]

    dt = DeviceToken.last
    assert_equal "ios", dt.platform
    assert dt.active?
  end

  test "POST create defaults platform to ios" do
    post "/api/v1/device_tokens",
      params: { token: "def456hextoken" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :created
    assert_equal "ios", DeviceToken.last.platform
  end

  test "POST create with existing token reactivates it" do
    dt = DeviceToken.create!(token: "existing-token", platform: "ios", active: false)

    assert_no_difference "DeviceToken.count" do
      post "/api/v1/device_tokens",
        params: { token: "existing-token", platform: "ios" }.to_json,
        headers: { "Content-Type" => "application/json" }
    end

    assert_response :created
    assert dt.reload.active?
  end

  test "POST create rejects blank token" do
    post "/api/v1/device_tokens",
      params: { token: "", platform: "ios" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :unprocessable_entity
  end
end
