require "test_helper"

class WorkspacePostsTest < ActionDispatch::IntegrationTest
  setup do
    @owner  = User.create!(email_address: "wp-o-#{SecureRandom.hex(4)}@example.com").tap { |u| u.update_column(:role, "admin") }
    @viewer = User.create!(email_address: "wp-v-#{SecureRandom.hex(4)}@example.com")
    @ws     = Workspace.create!(name: "Post WS", owner: @owner)
    @ws.memberships.create!(user: @viewer, role: "viewer")
    @acct = @ws.social_accounts.create!(
      platform: "x", connected_by: @owner, handle: "@magenta", external_id: SecureRandom.hex(4),
      access_token: "AT", refresh_token: "RT", token_expires_at: 2.hours.from_now,
      scopes: "tweet.write tweet.read users.read offline.access", status: "active"
    )
  end

  teardown do
    X::UserClient.http_stub = nil
    X::Oauth.http_stub = nil
  end

  test "posting hits X, persists tweet metadata on the WorkspacePost" do
    X::UserClient.http_stub = ->(method, url, payload, bearer) {
      assert_equal :post, method
      assert_equal "AT",  bearer
      { status: "201", body: { "data" => { "id" => "TID-1" } } }
    }

    sign_in_as(@owner)
    assert_difference -> { WorkspacePost.count }, 1 do
      post workspace_posts_path(workspace_slug: @ws.slug), params: { body: "hello world", target_platforms: ["x"] }
    end
    assert_redirected_to social_workspace_path(@ws.slug)

    wp = WorkspacePost.last
    assert_equal "posted", wp.status
    assert_equal "TID-1",  wp.remote_id
    assert_equal "https://x.com/magenta/status/TID-1", wp.remote_url
    assert wp.posted_at.present?
  end

  test "failed X response marks the post failed and stores the error" do
    X::UserClient.http_stub = ->(*) { { status: "403", body: { "detail" => "Duplicate" } } }
    sign_in_as(@owner)
    post workspace_posts_path(workspace_slug: @ws.slug), params: { body: "dup", target_platforms: ["x"] }
    wp = WorkspacePost.last
    assert_equal "failed", wp.status
    assert_match /403/, wp.error
    assert_match /Duplicate/, wp.error
  end

  test "401 triggers a refresh and retries once" do
    call_count = 0
    X::UserClient.http_stub = ->(method, url, payload, bearer) {
      call_count += 1
      if call_count == 1
        { status: "401", body: { "title" => "Unauthorized" } }
      else
        { status: "201", body: { "data" => { "id" => "RETRY-1" } } }
      end
    }
    refreshed = false
    X::Oauth.http_stub = ->(method, url, params, _headers) {
      refreshed = true if method == :post && params[:grant_type] == "refresh_token"
      ["200", { "access_token" => "NEW-AT", "refresh_token" => "NEW-RT", "expires_in" => 7200, "scope" => @acct.scopes }]
    }

    sign_in_as(@owner)
    post workspace_posts_path(workspace_slug: @ws.slug), params: { body: "retry", target_platforms: ["x"] }

    assert refreshed,           "refresh should have fired"
    assert_equal 2, call_count, "should retry once after refresh"
    assert_equal "RETRY-1", WorkspacePost.last.remote_id
    assert_equal "NEW-AT",  @acct.reload.access_token
  end

  test "viewer cannot post" do
    sign_in_as(@viewer)
    assert_no_difference -> { WorkspacePost.count } do
      post workspace_posts_path(workspace_slug: @ws.slug), params: { body: "no", target_platforms: ["x"] }
    end
  end

  test "trashcan is rendered for writers and hidden from viewers" do
    @ws.workspace_posts.create!(author: @owner, social_account: @acct, platform: "x",
      body: "see me", status: "posted", remote_id: "1", remote_url: "https://x.com/m/status/1", posted_at: Time.current)

    sign_in_as(@owner)
    get social_workspace_path(@ws.slug)
    assert_match %r{workspaces/#{@ws.slug}/posts/\d+}, response.body, "owner should see delete form"

    sign_in_as(@viewer)
    get social_workspace_path(@ws.slug)
    refute_match %r{workspaces/#{@ws.slug}/posts/\d+}, response.body, "viewer should NOT see delete form"
  end

  test "trashcan on a posted row calls X delete and drops the row" do
    wp = @ws.workspace_posts.create!(author: @owner, social_account: @acct, platform: "x",
      body: "del me", status: "posted", remote_id: "DEL-1",
      remote_url: "https://x.com/m/status/DEL-1", posted_at: Time.current)
    called = []
    X::UserClient.http_stub = ->(method, url, _payload, _bearer) {
      called << [method, url]
      { status: "200", body: { "data" => { "deleted" => true } } }
    }

    sign_in_as(@owner)
    assert_difference -> { WorkspacePost.count }, -1 do
      delete workspace_post_path(workspace_slug: @ws.slug, id: wp.id)
    end
    assert_equal [[:delete, "https://api.x.com/2/tweets/DEL-1"]], called
  end

  test "trashcan on a failed row drops the row without an X call" do
    wp = @ws.workspace_posts.create!(author: @owner, social_account: @acct, platform: "x",
      body: "nope", status: "failed", error: "boom")
    called = false
    X::UserClient.http_stub = ->(*) { called = true; { status: "200", body: {} } }

    sign_in_as(@owner)
    assert_difference -> { WorkspacePost.count }, -1 do
      delete workspace_post_path(workspace_slug: @ws.slug, id: wp.id)
    end
    refute called, "X should NOT be hit for a failed row"
  end

  test "X delete failure keeps the row and warns the user" do
    wp = @ws.workspace_posts.create!(author: @owner, social_account: @acct, platform: "x",
      body: "stays", status: "posted", remote_id: "K-1",
      remote_url: "https://x.com/m/status/K-1", posted_at: Time.current)
    X::UserClient.http_stub = ->(*) { { status: "403", body: { "detail" => "locked" } } }

    sign_in_as(@owner)
    assert_no_difference -> { WorkspacePost.count } do
      delete workspace_post_path(workspace_slug: @ws.slug, id: wp.id)
    end
    assert_match /Couldn't delete from X/, flash[:alert]
  end

  test "X 404 on delete is treated as already-gone and drops the row" do
    wp = @ws.workspace_posts.create!(author: @owner, social_account: @acct, platform: "x",
      body: "gone", status: "posted", remote_id: "G-1",
      remote_url: "https://x.com/m/status/G-1", posted_at: Time.current)
    X::UserClient.http_stub = ->(*) { { status: "404", body: {} } }

    sign_in_as(@owner)
    assert_difference -> { WorkspacePost.count }, -1 do
      delete workspace_post_path(workspace_slug: @ws.slug, id: wp.id)
    end
  end
end
