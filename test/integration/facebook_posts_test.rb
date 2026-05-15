require "test_helper"

class FacebookPostsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "fp-o-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @ws    = Workspace.create!(name: "FB Posts WS", owner: @owner)
    @fb    = @ws.social_accounts.create!(
      platform: "facebook", connected_by: @owner,
      handle: "Magenta NYC", display_name: "Magenta NYC",
      external_id: "555",
      access_token: "PAGE-AT",
      token_expires_at: nil, status: "active"
    )
  end

  teardown { Facebook::UserClient.http_stub = nil }

  test "post: hits /{page-id}/feed and stores both the full + permalink id" do
    Facebook::UserClient.http_stub = ->(method, url, params, _bearer) {
      assert_equal :post, method
      assert url.end_with?("/555/feed")
      assert_equal "hello facebook", params[:message]
      assert_equal "PAGE-AT", params[:access_token]
      { status: "200", body: { "id" => "555_98765" } }
    }

    sign_in_as(@owner)
    assert_difference -> { WorkspacePost.count }, 1 do
      post workspace_posts_path(workspace_slug: @ws.slug),
           params: { body: "hello facebook", target_platforms: ["facebook"] }
    end

    wp = WorkspacePost.last
    assert_equal "posted",   wp.status
    assert_equal "facebook", wp.platform
    assert_equal "555_98765", wp.remote_id
    assert_equal "https://www.facebook.com/555/posts/98765", wp.remote_url
  end

  test "401 marks the account needs_reauth" do
    Facebook::UserClient.http_stub = ->(*) {
      { status: "401", body: { "error" => { "message" => "Token expired" } } }
    }

    sign_in_as(@owner)
    post workspace_posts_path(workspace_slug: @ws.slug),
         params: { body: "broken", target_platforms: ["facebook"] }

    assert_equal "needs_reauth", @fb.reload.status
    assert_equal "failed",       WorkspacePost.last.status
  end

  test "trashcan deletes the FB post via Graph DELETE" do
    wp = @ws.workspace_posts.create!(author: @owner, social_account: @fb, platform: "facebook",
      body: "del", status: "posted", remote_id: "555_111",
      remote_url: "https://www.facebook.com/555/posts/111", posted_at: Time.current)
    called = []
    Facebook::UserClient.http_stub = ->(method, url, _params, _bearer) {
      called << [method, url]
      { status: "200", body: { "success" => true } }
    }

    sign_in_as(@owner)
    assert_difference -> { WorkspacePost.count }, -1 do
      delete workspace_post_path(workspace_slug: @ws.slug, id: wp.id)
    end
    assert called.any? { |m, u| m == :delete && u.end_with?("/555_111") }
  end

  test "fanout to all 4 platforms creates a row per platform" do
    @ws.social_accounts.create!(platform: "x", connected_by: @owner, handle: "@a", external_id: "x1",
      access_token: "X", refresh_token: "XR", token_expires_at: 2.hours.from_now, status: "active")
    @ws.social_accounts.create!(platform: "bluesky", connected_by: @owner, handle: "@a.bsky.social",
      external_id: "did:plc:b", access_token: "B", refresh_token: "BR", token_secret: "p",
      token_expires_at: 2.hours.from_now, status: "active")
    @ws.social_accounts.create!(platform: "threads", connected_by: @owner, handle: "@a", external_id: "t1",
      access_token: "T", token_expires_at: 60.days.from_now, status: "active")

    X::UserClient.http_stub        = ->(*) { { status: "201", body: { "data" => { "id" => "TID" } } } }
    Bluesky::UserClient.http_stub  = ->(*) { { status: "200", body: { "uri" => "at://did:plc:b/app.bsky.feed.post/BID" } } }
    Threads::UserClient.http_stub  = ->(method, url, _params, _bearer) {
      case
      when url.end_with?("/t1/threads")          then { status: "200", body: { "id" => "tc-1" } }
      when url.end_with?("/t1/threads_publish")  then { status: "200", body: { "id" => "TH-PID" } }
      when url.end_with?("/TH-PID")              then { status: "200", body: { "permalink" => "https://www.threads.net/@a/post/TH" } }
      end
    }
    Facebook::UserClient.http_stub = ->(*) { { status: "200", body: { "id" => "555_FBID" } } }

    sign_in_as(@owner)
    assert_difference -> { WorkspacePost.count }, 4 do
      post workspace_posts_path(workspace_slug: @ws.slug),
           params: { body: "everywhere", target_platforms: %w[x bluesky threads facebook] }
    end

    rows = @ws.workspace_posts.where(body: "everywhere").index_by(&:platform)
    assert_equal "TID",      rows["x"].remote_id
    assert_equal "BID",      rows["bluesky"].remote_id
    assert_equal "TH-PID",   rows["threads"].remote_id
    assert_equal "555_FBID", rows["facebook"].remote_id
    assert rows.values.all? { |r| r.status == "posted" }
  ensure
    X::UserClient.http_stub       = nil
    Bluesky::UserClient.http_stub = nil
    Threads::UserClient.http_stub = nil
  end
end
