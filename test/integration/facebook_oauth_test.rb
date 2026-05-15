require "test_helper"

class FacebookOauthTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "fb-o-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @ws    = Workspace.create!(name: "FB WS", owner: @owner)

    @orig_client_id     = Facebook::Oauth.method(:client_id)
    @orig_client_secret = Facebook::Oauth.method(:client_secret)
    Facebook::Oauth.define_singleton_method(:client_id)     { "stub-client" }
    Facebook::Oauth.define_singleton_method(:client_secret) { "stub-secret" }
  end

  teardown do
    Facebook::Oauth.http_stub = nil
    orig_id     = @orig_client_id
    orig_secret = @orig_client_secret
    Facebook::Oauth.define_singleton_method(:client_id)     { orig_id.call }
    Facebook::Oauth.define_singleton_method(:client_secret) { orig_secret.call }
  end

  test "connect redirects to facebook authorize URL with required params" do
    sign_in_as(@owner)
    post workspace_oauth_facebook_connect_path(workspace_slug: @ws.slug)
    assert_response :redirect
    loc = response.headers["Location"]
    assert loc.start_with?(Facebook::Oauth::AUTHORIZE_URL)

    params = Rack::Utils.parse_query(URI(loc).query)
    assert_equal "stub-client", params["client_id"]
    assert_equal "code",        params["response_type"]
    assert params["state"].present?
    assert_includes params["scope"], "pages_manage_posts"
  end

  test "callback exchanges, picks first Page, persists SocialAccount with page token" do
    Facebook::Oauth.http_stub = ->(method, url, params, _headers) {
      case
      when url == Facebook::Oauth::TOKEN_URL && params[:grant_type] == "fb_exchange_token"
        ["200", { "access_token" => "LONG-USER-AT", "expires_in" => 5_184_000 }]
      when url == Facebook::Oauth::TOKEN_URL
        ["200", { "access_token" => "SHORT-USER-AT", "expires_in" => 3600 }]
      when url == Facebook::Oauth::ME_ACCOUNTS_URL
        ["200", { "data" => [
          { "id" => "555", "name" => "Magenta NYC", "access_token" => "PAGE-AT-555" }
        ] }]
      else
        raise "unexpected #{method} #{url}"
      end
    }

    sign_in_as(@owner)
    post workspace_oauth_facebook_connect_path(workspace_slug: @ws.slug)
    state = Rack::Utils.parse_query(URI(response.headers["Location"]).query)["state"]

    assert_difference -> { SocialAccount.count }, 1 do
      get oauth_facebook_callback_path, params: { code: "fake", state: state }
    end
    assert_response :redirect

    acct = @ws.social_accounts.last
    assert_equal "facebook",     acct.platform
    assert_equal "555",          acct.external_id
    assert_equal "Magenta NYC",  acct.handle
    assert_equal "PAGE-AT-555",  acct.access_token
    assert_equal "active",       acct.status
    assert_nil acct.token_expires_at, "Page tokens are effectively permanent"
  end

  test "no Pages on the account redirects with a friendly error" do
    Facebook::Oauth.http_stub = ->(method, url, params, _headers) {
      case
      when url == Facebook::Oauth::TOKEN_URL && params[:grant_type] == "fb_exchange_token"
        ["200", { "access_token" => "LONG-AT" }]
      when url == Facebook::Oauth::TOKEN_URL
        ["200", { "access_token" => "SHORT-AT" }]
      when url == Facebook::Oauth::ME_ACCOUNTS_URL
        ["200", { "data" => [] }]
      end
    }

    sign_in_as(@owner)
    post workspace_oauth_facebook_connect_path(workspace_slug: @ws.slug)
    state = Rack::Utils.parse_query(URI(response.headers["Location"]).query)["state"]

    assert_no_difference -> { SocialAccount.count } do
      get oauth_facebook_callback_path, params: { code: "fake", state: state }
    end
    assert_match /No Facebook Pages/, flash[:alert]
  end

  test "non-admin can't initiate connect" do
    viewer = User.create!(email_address: "fb-v-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: viewer, role: "viewer")
    sign_in_as(viewer)
    post workspace_oauth_facebook_connect_path(workspace_slug: @ws.slug)
    assert_response :redirect
  end

  test "missing credentials redirects with setup hint" do
    Facebook::Oauth.define_singleton_method(:client_id)     { nil }
    Facebook::Oauth.define_singleton_method(:client_secret) { nil }
    sign_in_as(@owner)
    post workspace_oauth_facebook_connect_path(workspace_slug: @ws.slug)
    assert_response :redirect
    assert_match /not configured/, flash[:alert]
  end
end
