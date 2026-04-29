require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "correct-horse")
  end

  test "GET show redirects when unauthenticated" do
    get settings_path
    assert_redirected_to new_session_path
  end

  test "GET show renders when authenticated" do
    sign_in_as @user
    get settings_path
    assert_response :success
    assert_select "h1", text: "Settings"
  end

  test "POST verify_password returns 204 for matching password" do
    sign_in_as @user
    post verify_password_settings_path,
      params: { password: "correct-horse" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :no_content
  end

  test "POST verify_password returns 401 for wrong password" do
    sign_in_as @user
    post verify_password_settings_path,
      params: { password: "wrong" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "POST verify_password redirects when unauthenticated" do
    post verify_password_settings_path,
      params: { password: "anything" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_redirected_to new_session_path
  end

  test "DELETE settings destroys the user with correct password" do
    sign_in_as @user
    user_id = @user.id

    assert_difference -> { User.count }, -1 do
      delete settings_path, params: { password: "correct-horse" }
    end

    assert_redirected_to root_path
    assert_nil User.find_by(id: user_id)
    assert_nil cookies[:session_id].presence
  end

  test "DELETE settings does not destroy the user with wrong password" do
    sign_in_as @user

    assert_no_difference "User.count" do
      delete settings_path, params: { password: "wrong" }
    end

    assert_redirected_to settings_path
    assert_match(/incorrect/i, flash[:alert])
  end

  test "DELETE settings redirects when unauthenticated" do
    delete settings_path, params: { password: "anything" }
    assert_redirected_to new_session_path
  end

  test "DELETE settings for nostr-only user requires DELETE confirmation phrase" do
    nostr_user = User.create!(pubkey_hex: "a" * 64)
    sign_in_as nostr_user

    assert_no_difference "User.count" do
      delete settings_path, params: { confirm: "nope" }
    end
    assert_redirected_to settings_path

    assert_difference -> { User.count }, -1 do
      delete settings_path, params: { confirm: "DELETE" }
    end
    assert_redirected_to root_path
  end
end
