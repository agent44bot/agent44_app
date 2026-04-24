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

  test "POST create associates token with user when user_id is provided" do
    user = users(:one)
    post "/api/v1/device_tokens",
      params: { token: "user-scoped-token", platform: "ios", user_id: user.id }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :created
    assert_equal user.id, DeviceToken.find_by(token: "user-scoped-token").user_id
  end

  test "POST create ignores unknown user_id" do
    post "/api/v1/device_tokens",
      params: { token: "orphan-token", platform: "ios", user_id: 999_999 }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :created
    assert_nil DeviceToken.find_by(token: "orphan-token").user_id
  end
end
