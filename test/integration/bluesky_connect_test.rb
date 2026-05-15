require "test_helper"

class BlueskyConnectTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "bsk-o-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @ws    = Workspace.create!(name: "Bsky WS", owner: @owner)
  end

  teardown { Bluesky::Session.http_stub = nil }

  test "admin can connect a Bluesky account with valid handle + app password" do
    Bluesky::Session.http_stub = ->(method, url, payload, _headers) {
      assert_equal :post, method
      assert url.end_with?("/com.atproto.server.createSession")
      assert_equal "agent44.bsky.social", payload[:identifier]
      assert_equal "good-pw", payload[:password]
      ["200", { "did" => "did:plc:abc", "handle" => "agent44.bsky.social",
                "accessJwt" => "AT-JWT", "refreshJwt" => "REF-JWT" }]
    }

    sign_in_as(@owner)

    get new_workspace_bluesky_account_path(workspace_slug: @ws.slug)
    assert_response :success
    assert_match /app password/i, response.body

    assert_difference -> { SocialAccount.count }, 1 do
      post workspace_bluesky_account_path(workspace_slug: @ws.slug),
           params: { handle: "agent44.bsky.social", app_password: "good-pw" }
    end
    assert_response :redirect

    acct = @ws.social_accounts.for_platform("bluesky").first
    assert_equal "@agent44.bsky.social", acct.handle
    assert_equal "did:plc:abc",          acct.external_id
    assert_equal "AT-JWT",               acct.access_token
    assert_equal "REF-JWT",              acct.refresh_token
    assert_equal "good-pw",              acct.token_secret
    assert_equal "active",               acct.status
  end

  test "Bluesky rejecting credentials shows the form with an error and creates no account" do
    Bluesky::Session.http_stub = ->(*) {
      ["401", { "error" => "AuthenticationRequired", "message" => "Invalid identifier or password" }]
    }
    sign_in_as(@owner)

    assert_no_difference -> { SocialAccount.count } do
      post workspace_bluesky_account_path(workspace_slug: @ws.slug),
           params: { handle: "agent44.bsky.social", app_password: "wrong" }
    end
    assert_response :unprocessable_entity
    assert_match /Bluesky rejected/, response.body
  end

  test "missing fields render the form with an error" do
    sign_in_as(@owner)
    post workspace_bluesky_account_path(workspace_slug: @ws.slug),
         params: { handle: "", app_password: "" }
    assert_response :unprocessable_entity
    assert_match /both required/i, response.body
  end

  test "non-admin can't connect" do
    viewer = User.create!(email_address: "bsk-v-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: viewer, role: "viewer")
    sign_in_as(viewer)
    post workspace_bluesky_account_path(workspace_slug: @ws.slug),
         params: { handle: "x.bsky.social", app_password: "y" }
    assert_response :redirect
    assert_equal 0, @ws.social_accounts.count
  end
end
