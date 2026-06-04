require "test_helper"

class XOauthTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "xo-o-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @ws    = Workspace.create!(name: "OAuth WS", owner: @owner)

    # Force credentials presence regardless of test env config. Save the
    # originals so teardown can restore them — never remove_method, because
    # X::Oauth defines client_id/client_secret at load time and other tests
    # in the same process depend on them.
    @orig_client_id     = X::Oauth.method(:client_id)
    @orig_client_secret = X::Oauth.method(:client_secret)
    X::Oauth.define_singleton_method(:client_id)     { "stub-client" }
    X::Oauth.define_singleton_method(:client_secret) { "stub-secret" }
  end

  teardown do
    X::Oauth.http_stub = nil
    orig_id     = @orig_client_id
    orig_secret = @orig_client_secret
    X::Oauth.define_singleton_method(:client_id)     { orig_id.call }
    X::Oauth.define_singleton_method(:client_secret) { orig_secret.call }
  end

  test "connect redirects to X authorize URL with required params" do
    sign_in_as(@owner)
    post workspace_oauth_x_connect_path(workspace_slug: @ws.slug)
    assert_response :redirect
    loc = response.headers["Location"]
    assert loc.start_with?(X::Oauth::AUTHORIZE_URL), "expected authorize URL, got #{loc}"

    params = Rack::Utils.parse_query(URI(loc).query)
    assert_equal "stub-client", params["client_id"]
    assert_equal "S256",        params["code_challenge_method"]
    assert params["state"].present?
    assert params["code_challenge"].present?
    assert_includes params["scope"], "tweet.write"
  end

  test "callback exchanges code, fetches profile, and persists SocialAccount" do
    X::Oauth.http_stub = ->(method, url, params, headers) {
      case [ method, url ]
      when [ :post, X::Oauth::TOKEN_URL ]
        [ "200", { "access_token" => "AT", "refresh_token" => "RT", "expires_in" => 7200,
                  "scope" => "tweet.read tweet.write users.read offline.access", "token_type" => "bearer" } ]
      when [ :get, X::Oauth::ME_URL ]
        assert_equal "Bearer AT", headers["Authorization"]
        [ "200", { "data" => { "id" => "42", "username" => "magenta", "name" => "Magenta" } } ]
      else
        raise "unexpected #{method} #{url}"
      end
    }

    sign_in_as(@owner)
    post workspace_oauth_x_connect_path(workspace_slug: @ws.slug)
    state = Rack::Utils.parse_query(URI(response.headers["Location"]).query)["state"]

    assert_difference -> { SocialAccount.count }, 1 do
      get oauth_x_callback_path, params: { code: "fake", state: state }
    end
    assert_response :redirect

    acct = @ws.social_accounts.last
    assert_equal "x",         acct.platform
    assert_equal "@magenta",  acct.handle
    assert_equal "42",        acct.external_id
    assert_equal "active",    acct.status
    assert_equal "AT",        acct.access_token
    assert_equal "RT",        acct.refresh_token
    assert acct.token_expires_at > 1.hour.from_now
  end

  test "state mismatch on callback redirects with alert" do
    sign_in_as(@owner)
    post workspace_oauth_x_connect_path(workspace_slug: @ws.slug)

    assert_no_difference -> { SocialAccount.count } do
      get oauth_x_callback_path, params: { code: "x", state: "wrong" }
    end
    assert_match /state mismatch/i, flash[:alert]
  end

  test "X access_denied redirects with alert and no account is created" do
    sign_in_as(@owner)
    post workspace_oauth_x_connect_path(workspace_slug: @ws.slug)
    state = Rack::Utils.parse_query(URI(response.headers["Location"]).query)["state"]

    assert_no_difference -> { SocialAccount.count } do
      get oauth_x_callback_path, params: { error: "access_denied", state: state }
    end
    assert_match /declined/i, flash[:alert]
  end

  test "non-admin cannot initiate connect" do
    viewer = User.create!(email_address: "xo-v-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: viewer, role: "viewer")
    sign_in_as(viewer)
    post workspace_oauth_x_connect_path(workspace_slug: @ws.slug)
    assert_response :redirect
  end
end
