require "test_helper"

class ThreadsOauthTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "th-o-#{SecureRandom.hex(4)}@example.com")
    @ws    = Workspace.create!(name: "Threads WS", owner: @owner)

    @orig_client_id     = Threads::Oauth.method(:client_id)
    @orig_client_secret = Threads::Oauth.method(:client_secret)
    Threads::Oauth.define_singleton_method(:client_id)     { "stub-client" }
    Threads::Oauth.define_singleton_method(:client_secret) { "stub-secret" }
  end

  teardown do
    Threads::Oauth.http_stub = nil
    orig_id     = @orig_client_id
    orig_secret = @orig_client_secret
    Threads::Oauth.define_singleton_method(:client_id)     { orig_id.call }
    Threads::Oauth.define_singleton_method(:client_secret) { orig_secret.call }
  end

  test "connect redirects to threads.net authorize URL with required params" do
    sign_in_as(@owner)
    post workspace_oauth_threads_connect_path(workspace_slug: @ws.slug)
    assert_response :redirect
    loc = response.headers["Location"]
    assert loc.start_with?(Threads::Oauth::AUTHORIZE_URL)

    params = Rack::Utils.parse_query(URI(loc).query)
    assert_equal "stub-client", params["client_id"]
    assert_equal "code",        params["response_type"]
    assert params["state"].present?
    assert_includes params["scope"], "threads_content_publish"
  end

  test "callback exchanges code, swaps short→long, fetches profile, persists SocialAccount" do
    Threads::Oauth.http_stub = ->(method, url, _params, _headers) {
      case url
      when Threads::Oauth::TOKEN_URL
        ["200", { "access_token" => "SHORT-AT", "user_id" => "777" }]
      when Threads::Oauth::LONG_LIVED_URL
        ["200", { "access_token" => "LONG-AT", "expires_in" => 5_184_000 }] # 60d
      when Threads::Oauth::ME_URL
        ["200", { "id" => "777", "username" => "agent44labs", "name" => "Agent 44 Labs" }]
      else
        raise "unexpected #{url}"
      end
    }

    sign_in_as(@owner)
    post workspace_oauth_threads_connect_path(workspace_slug: @ws.slug)
    state = Rack::Utils.parse_query(URI(response.headers["Location"]).query)["state"]

    assert_difference -> { SocialAccount.count }, 1 do
      get oauth_threads_callback_path, params: { code: "fake", state: state }
    end
    assert_redirected_to workspace_path(@ws.slug)

    acct = @ws.social_accounts.last
    assert_equal "threads",      acct.platform
    assert_equal "@agent44labs", acct.handle
    assert_equal "777",          acct.external_id
    assert_equal "active",       acct.status
    assert_equal "LONG-AT",      acct.access_token
    assert acct.token_expires_at > 30.days.from_now
  end

  test "state mismatch on callback redirects with alert" do
    sign_in_as(@owner)
    post workspace_oauth_threads_connect_path(workspace_slug: @ws.slug)
    assert_no_difference -> { SocialAccount.count } do
      get oauth_threads_callback_path, params: { code: "x", state: "wrong" }
    end
    assert_match /state mismatch/i, flash[:alert]
  end

  test "user-declined redirect surfaces the alert" do
    sign_in_as(@owner)
    post workspace_oauth_threads_connect_path(workspace_slug: @ws.slug)
    state = Rack::Utils.parse_query(URI(response.headers["Location"]).query)["state"]

    assert_no_difference -> { SocialAccount.count } do
      get oauth_threads_callback_path, params: { error: "access_denied", state: state }
    end
    assert_match /declined/i, flash[:alert]
  end

  test "non-admin can't initiate connect" do
    viewer = User.create!(email_address: "th-v-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: viewer, role: "viewer")
    sign_in_as(viewer)
    post workspace_oauth_threads_connect_path(workspace_slug: @ws.slug)
    assert_redirected_to workspace_path(@ws.slug)
  end
end
