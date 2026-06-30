require "test_helper"

class RefreshXTokensJobTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email_address: "rxt-#{SecureRandom.hex(4)}@example.com")
    @ws    = Workspace.create!(name: "X Tokens WS", owner: @owner)
    @acct  = @ws.social_accounts.create!(
      platform: "x", connected_by: @owner, handle: "@a", external_id: "1",
      access_token: "OLD_AT", refresh_token: "OLD_RT",
      token_expires_at: 5.minutes.from_now, # inside the 30-min refresh window
      status: "active"
    )
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

  test "a successful refresh rotates the tokens and keeps the account active" do
    X::Oauth.http_stub = ->(_method, _url, _params, _headers) {
      [ "200", { "access_token" => "NEW_AT", "refresh_token" => "NEW_RT",
                 "expires_in" => 7200, "scope" => "tweet.read tweet.write", "token_type" => "bearer" } ]
    }
    RefreshXTokensJob.new.perform
    @acct.reload
    assert_equal "active", @acct.status
    assert_equal "NEW_AT", @acct.access_token
    assert_equal "NEW_RT", @acct.refresh_token
  end

  test "a transient X failure (503) leaves the account active so it retries, not needs_reauth" do
    X::Oauth.http_stub = ->(_method, _url, _params, _headers) {
      [ "503", { "title" => "Service Unavailable" } ]
    }
    RefreshXTokensJob.new.perform
    @acct.reload
    assert_equal "active", @acct.status, "a 503 must not strand the account on manual reconnect"
    assert_equal "OLD_RT", @acct.refresh_token, "tokens untouched on a transient failure"
  end

  test "a network error (no HTTP status) is treated as transient" do
    X::Oauth.http_stub = ->(_method, _url, _params, _headers) { raise SocketError, "getaddrinfo" }
    RefreshXTokensJob.new.perform
    @acct.reload
    assert_equal "active", @acct.status
  end

  test "a real auth rejection (400 invalid_grant) marks the account needs_reauth" do
    X::Oauth.http_stub = ->(_method, _url, _params, _headers) {
      [ "400", { "error" => "invalid_grant", "error_description" => "refresh token revoked" } ]
    }
    RefreshXTokensJob.new.perform
    @acct.reload
    assert_equal "needs_reauth", @acct.status
  end

  test "retryable? classifies 5xx and network failures, not 4xx" do
    assert X::Oauth::TokenResult.new(ok?: false, status: "503").retryable?
    assert X::Oauth::TokenResult.new(ok?: false, status: "429").retryable?
    assert X::Oauth::TokenResult.new(ok?: false, status: nil).retryable?
    refute X::Oauth::TokenResult.new(ok?: false, status: "400").retryable?
    refute X::Oauth::TokenResult.new(ok?: false, status: "401").retryable?
    refute X::Oauth::TokenResult.new(ok?: true,  status: "200").retryable?
  end
end
