require "test_helper"
require "webauthn/fake_client"

class PasskeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user   = User.create!(email_address: "pk-#{SecureRandom.hex(4)}@example.com")
    @origin = "http://localhost:3000" # matches WebAuthn allowed_origins in test
    @client = WebAuthn::FakeClient.new(@origin)
  end

  # Drive the registration ceremony with a fake authenticator; returns the
  # created Credential's external_id.
  def register_passkey(user: @user, client: @client)
    sign_in_as(user)
    post passkey_create_challenge_path
    challenge = JSON.parse(response.body)["challenge"]
    post passkeys_path, params: client.create(challenge: challenge), as: :json
    JSON.parse(response.body)
  end

  test "registration stores a passkey for the signed-in user" do
    sign_in_as(@user)
    post passkey_create_challenge_path
    assert_response :success
    challenge = JSON.parse(response.body)["challenge"]

    assert_difference -> { @user.credentials.count }, 1 do
      post passkeys_path, params: @client.create(challenge: challenge), as: :json
    end
    assert_response :created
    assert @user.reload.webauthn_id.present?, "user handle generated on registration"
  end

  test "round trip: register then sign in with the passkey (usernameless)" do
    register_passkey
    assert_response :created
    delete session_path # sign out

    post passkey_auth_challenge_path
    assert_response :success
    challenge = JSON.parse(response.body)["challenge"]

    post passkey_authenticate_path, params: @client.get(challenge: challenge), as: :json
    assert_response :success
    assert_equal workspaces_url, JSON.parse(response.body)["redirect_to"]
    assert cookies[:session_id].present?, "a session is started"
    assert @user.credentials.first.reload.last_used_at.present?
  end

  test "authentication is rejected without a challenge" do
    post passkey_authenticate_path, params: { id: "x", type: "public-key", rawId: "x", response: {} }, as: :json
    assert_response :unprocessable_entity
  end

  test "authentication is rejected for a passkey we never registered" do
    rogue = WebAuthn::FakeClient.new(@origin)
    rogue.create(challenge: Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false))

    post passkey_auth_challenge_path
    challenge = JSON.parse(response.body)["challenge"]
    post passkey_authenticate_path, params: rogue.get(challenge: challenge), as: :json
    assert_response :unprocessable_entity
  end

  test "a user can remove their passkey" do
    register_passkey
    credential = @user.credentials.first
    sign_in_as(@user)
    assert_difference -> { @user.credentials.count }, -1 do
      delete passkey_path(credential)
    end
    assert_redirected_to settings_path
  end

  test "registration requires sign-in" do
    post passkey_create_challenge_path
    assert_response :redirect # bounced to sign-in
  end
end
