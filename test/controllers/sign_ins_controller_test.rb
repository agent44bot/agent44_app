require "test_helper"

class SignInsControllerTest < ActionDispatch::IntegrationTest
  test "new renders the email screen" do
    get sign_in_path
    assert_response :success
    assert_select "input[name=email_address]"
  end

  test "create emails a code and advances to the code screen without creating a user" do
    assert_no_difference -> { User.count } do
      assert_difference -> { LoginCode.count }, 1 do
        post sign_in_path, params: { email_address: "New.User@Example.com" }
      end
    end
    assert_enqueued_emails 1
    assert_redirected_to sign_in_code_path
  end

  test "create with an invalid email re-renders and sends nothing" do
    assert_no_difference -> { LoginCode.count } do
      post sign_in_path, params: { email_address: "not-an-email" }
    end
    assert_enqueued_emails 0
    assert_response :unprocessable_entity
  end

  test "create behaves identically for known and unknown emails (enumeration-safe)" do
    existing = User.create!(email_address: "known-#{SecureRandom.hex(4)}@example.com")
    post sign_in_path, params: { email_address: existing.email_address }
    assert_redirected_to sign_in_code_path

    post sign_in_path, params: { email_address: "unknown-#{SecureRandom.hex(4)}@example.com" }
    assert_redirected_to sign_in_code_path
  end

  test "verify with the right code signs in, creating + verifying a new account" do
    email = "fresh-#{SecureRandom.hex(4)}@example.com"
    _record, code = LoginCode.issue!(email_address: email)

    assert_difference -> { User.count }, 1 do
      post verify_sign_in_path, params: { email_address: email, code: code }
    end
    assert_redirected_to workspaces_url
    user = User.find_by(email_address: email)
    assert user.email_verified?, "passwordless sign-in should verify the email"
    assert user.sessions.any?
    assert cookies[:session_id].present?
  end

  test "verify into an existing account does not duplicate the user" do
    existing = User.create!(email_address: "ret-#{SecureRandom.hex(4)}@example.com")
    _r, code = LoginCode.issue!(email_address: existing.email_address)
    assert_no_difference -> { User.count } do
      post verify_sign_in_path, params: { email_address: existing.email_address, code: code }
    end
    assert_redirected_to workspaces_url
  end

  test "verify with a wrong code fails and creates no session/account" do
    email = "x-#{SecureRandom.hex(4)}@example.com"
    _r, code = LoginCode.issue!(email_address: email)
    wrong = code == "000000" ? "999999" : "000000"
    post verify_sign_in_path, params: { email_address: email, code: wrong }
    assert_response :unprocessable_entity
    assert_nil User.find_by(email_address: email)
  end

  test "a consumed code cannot be reused" do
    email = "y-#{SecureRandom.hex(4)}@example.com"
    _r, code = LoginCode.issue!(email_address: email)
    post verify_sign_in_path, params: { email_address: email, code: code }
    assert_redirected_to workspaces_url

    post verify_sign_in_path, params: { email_address: email, code: code }
    assert_response :unprocessable_entity
  end

  test "magic link signs in via a valid token" do
    email = "link-#{SecureRandom.hex(4)}@example.com"
    record, _code = LoginCode.issue!(email_address: email)
    get sign_in_link_path(token: record.generate_token_for(:link))
    assert_redirected_to workspaces_url
    assert User.find_by(email_address: email)
  end

  test "magic link rejects an invalid token" do
    get sign_in_link_path(token: "garbage")
    assert_redirected_to sign_in_path
  end

  test "authenticated visitors skip the email screen" do
    sign_in_as User.create!(email_address: "auth-#{SecureRandom.hex(4)}@example.com")
    get sign_in_path
    assert_redirected_to workspaces_url
  end
end
