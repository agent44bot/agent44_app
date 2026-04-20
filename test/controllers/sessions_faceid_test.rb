require "test_helper"

class SessionsFaceIdTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.find_by(email_address: "botwhisperer@hey.com") || users(:one)
  end

  test "sign-in page renders Face ID button markup (hidden by default)" do
    get new_session_path
    assert_response :success
    assert_select "button#faceid-signin-btn"
    # Button should be hidden by default (only shown by JS in Capacitor)
    assert_match 'display:none', response.body
  end

  test "sign-in page includes faceid_auth JS partial" do
    get new_session_path
    assert_response :success
    # The JS checks for Capacitor and BiometricAuth plugin
    assert_match "BiometricAuth", response.body
    assert_match "isAvailable", response.body
    assert_match "saveCredentials", response.body
  end

  test "homepage shows Face ID button for signed-out users" do
    get root_path
    assert_response :success
    assert_select "button#faceid-signin-btn"
  end

  test "homepage shows Face ID button even for signed-in users on mobile" do
    post session_path, params: { email_address: @user.email_address, password: "password" }
    follow_redirect!

    get root_path
    assert_response :success
    assert_select "button#faceid-signin-btn"
  end

  test "sign-in form saves credentials on submit via JS" do
    get new_session_path
    assert_response :success
    # JS binds to form submit to call saveCredentials
    assert_match "faceidBound", response.body
    assert_match "saveCredentials", response.body
  end

  test "Face ID JS creates hidden form targeting session_path" do
    get new_session_path
    assert_response :success
    assert_match %r{form\.action\s*=\s*"/session"}, response.body
    assert_match "email_address", response.body
    assert_match "authenticity_token", response.body
  end
end
