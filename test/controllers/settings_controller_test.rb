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
end
