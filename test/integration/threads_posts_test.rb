require "test_helper"

class ThreadsPostsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email_address: "tp-o-#{SecureRandom.hex(4)}@example.com")
    @ws    = Workspace.create!(name: "Threads Posts WS", owner: @owner)
    @th    = @ws.social_accounts.create!(
      platform: "threads", connected_by: @owner,
      handle: "@agent44labs", display_name: "Agent 44 Labs",
      external_id: "777",
      access_token: "LONG-AT",
      token_expires_at: 60.days.from_now, status: "active"
    )
  end

  teardown do
    Threads::UserClient.http_stub = nil
    Threads::Oauth.http_stub      = nil
  end

  test "post: creates container then publishes, fetches permalink" do
    seq = []
    Threads::UserClient.http_stub = ->(method, url, params, _bearer) {
      seq << url
      if url.end_with?("/777/threads")
        assert_equal :post, method
        assert_equal "TEXT", params[:media_type]
        assert_equal "hello threads", params[:text]
        { status: "200", body: { "id" => "container-1" } }
      elsif url.end_with?("/777/threads_publish")
        assert_equal "container-1", params[:creation_id]
        { status: "200", body: { "id" => "post-9" } }
      elsif url.end_with?("/post-9")
        { status: "200", body: { "id" => "post-9", "permalink" => "https://www.threads.net/@agent44labs/post/abc123" } }
      else
        raise "unexpected #{url}"
      end
    }

    sign_in_as(@owner)
    assert_difference -> { WorkspacePost.count }, 1 do
      post workspace_posts_path(workspace_slug: @ws.slug),
           params: { body: "hello threads", target_platforms: ["threads"] }
    end

    wp = WorkspacePost.last
    assert_equal "posted",  wp.status
    assert_equal "threads", wp.platform
    assert_equal "post-9",  wp.remote_id
    assert_equal "https://www.threads.net/@agent44labs/post/abc123", wp.remote_url
    assert_equal 3, seq.size, "should hit container, publish, then permalink"
  end

  test "container 401 triggers refresh + retry" do
    call_count = 0
    Threads::UserClient.http_stub = ->(method, url, params, _bearer) {
      if url.end_with?("/777/threads")
        call_count += 1
        if call_count == 1
          { status: "401", body: { "error" => { "message" => "Token expired" } } }
        else
          { status: "200", body: { "id" => "container-2" } }
        end
      elsif url.end_with?("/777/threads_publish")
        { status: "200", body: { "id" => "post-2" } }
      elsif url.end_with?("/post-2")
        { status: "200", body: { "permalink" => "https://www.threads.net/@agent44labs/post/p2" } }
      else
        raise "unexpected #{url}"
      end
    }
    refreshed = false
    Threads::Oauth.http_stub = ->(method, url, params, _headers) {
      if url == Threads::Oauth::REFRESH_URL && params[:grant_type] == "th_refresh_token"
        refreshed = true
        ["200", { "access_token" => "REFRESHED-AT", "expires_in" => 5_184_000 }]
      else
        raise "unexpected oauth call #{url}"
      end
    }

    sign_in_as(@owner)
    post workspace_posts_path(workspace_slug: @ws.slug),
         params: { body: "after 401", target_platforms: ["threads"] }

    assert refreshed, "Threads refresh should have fired on 401"
    assert_equal "REFRESHED-AT", @th.reload.access_token
    assert_equal "post-2", WorkspacePost.last.remote_id
  end

  test "trashcan calls delete and drops the row" do
    wp = @ws.workspace_posts.create!(author: @owner, social_account: @th, platform: "threads",
      body: "del me", status: "posted", remote_id: "post-del",
      remote_url: "https://www.threads.net/@agent44labs/post/abc", posted_at: Time.current)
    called = []
    Threads::UserClient.http_stub = ->(method, url, _params, _bearer) {
      called << [method, url]
      { status: "200", body: { "success" => true } }
    }

    sign_in_as(@owner)
    assert_difference -> { WorkspacePost.count }, -1 do
      delete workspace_post_path(workspace_slug: @ws.slug, id: wp.id)
    end
    assert called.any? { |m, u| m == :delete && u.end_with?("/post-del") }
  end

  test "three-platform fanout (X + Bluesky + Threads) creates a row per platform" do
    @ws.social_accounts.create!(platform: "x", connected_by: @owner, handle: "@agent44", external_id: "x1",
      access_token: "X-AT", refresh_token: "X-RT", token_expires_at: 2.hours.from_now, status: "active")
    @ws.social_accounts.create!(platform: "bluesky", connected_by: @owner, handle: "@agent44.bsky.social",
      external_id: "did:plc:abc", access_token: "B-AT", refresh_token: "B-RT", token_secret: "pw",
      token_expires_at: 2.hours.from_now, status: "active")

    X::UserClient.http_stub       = ->(*) { { status: "201", body: { "data" => { "id" => "TID" } } } }
    Bluesky::UserClient.http_stub = ->(*) { { status: "200", body: { "uri" => "at://did:plc:abc/app.bsky.feed.post/BID" } } }
    Threads::UserClient.http_stub = ->(method, url, _params, _bearer) {
      case
      when url.end_with?("/777/threads")          then { status: "200", body: { "id" => "container-x" } }
      when url.end_with?("/777/threads_publish")  then { status: "200", body: { "id" => "TH-POST" } }
      when url.end_with?("/TH-POST")              then { status: "200", body: { "permalink" => "https://www.threads.net/@agent44labs/post/THP" } }
      else raise "unexpected #{url}"
      end
    }

    sign_in_as(@owner)
    assert_difference -> { WorkspacePost.count }, 3 do
      post workspace_posts_path(workspace_slug: @ws.slug),
           params: { body: "everywhere", target_platforms: %w[x bluesky threads] }
    end

    rows = @ws.workspace_posts.where(body: "everywhere").index_by(&:platform)
    assert_equal "TID",     rows["x"].remote_id
    assert_equal "BID",     rows["bluesky"].remote_id
    assert_equal "TH-POST", rows["threads"].remote_id
    assert_equal "https://www.threads.net/@agent44labs/post/THP", rows["threads"].remote_url
    assert rows.values.all? { |r| r.status == "posted" }
  ensure
    X::UserClient.http_stub       = nil
    Bluesky::UserClient.http_stub = nil
  end
end
