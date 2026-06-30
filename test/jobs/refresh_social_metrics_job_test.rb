require "test_helper"

class RefreshSocialMetricsJobTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email_address: "rsm-#{SecureRandom.hex(4)}@example.com")
    @ws    = Workspace.create!(name: "Metrics WS", owner: @owner)
    @x_acct = @ws.social_accounts.create!(platform: "x", connected_by: @owner, handle: "@a", external_id: "1",
      access_token: "AT", refresh_token: "RT", token_expires_at: 2.hours.from_now, status: "active")
    @b_acct = @ws.social_accounts.create!(platform: "bluesky", connected_by: @owner, handle: "@a.bsky.social",
      external_id: "did:plc:abc", access_token: "BAT", refresh_token: "BRT", token_secret: "pw",
      token_expires_at: 2.hours.from_now, status: "active")
  end

  teardown do
    X::UserClient.http_stub = nil
    Bluesky::UserClient.http_stub = nil
  end

  test "fetches X + Bluesky metrics for fresh posts, writes onto the row" do
    x_post  = posted!(@x_acct, "x", "TID-1")
    bsk_post = posted!(@b_acct, "bluesky", "rkey-1")

    X::UserClient.http_stub = ->(method, url, _payload, _bearer) {
      assert_equal :get, method
      assert url.include?("/2/tweets/TID-1")
      { status: "200", body: { "data" => { "id" => "TID-1", "public_metrics" => {
        "impression_count" => 1200, "like_count" => 47, "retweet_count" => 5,
        "reply_count" => 3, "quote_count" => 1, "bookmark_count" => 9
      } } } }
    }
    Bluesky::UserClient.http_stub = ->(method, url, _payload, _bearer) {
      assert_equal :get, method
      assert url.include?("getPosts")
      assert url.include?("rkey-1")
      { status: "200", body: { "posts" => [
        { "uri" => "at://did:plc:abc/app.bsky.feed.post/rkey-1",
          "likeCount" => 22, "repostCount" => 4, "replyCount" => 2, "quoteCount" => 0 }
      ] } }
    }

    RefreshSocialMetricsJob.new.perform

    x_post.reload
    assert_equal 1200, x_post.impressions
    assert_equal 47,   x_post.likes
    assert_equal 5,    x_post.reposts
    assert_equal 3,    x_post.replies
    assert_equal 1,    x_post.quotes
    assert_equal 9,    x_post.bookmarks
    assert x_post.metrics_synced_at.present?

    bsk_post.reload
    assert_equal 22, bsk_post.likes
    assert_equal 4,  bsk_post.reposts
    assert_equal 2,  bsk_post.replies
    assert_equal 0,  bsk_post.impressions, "Bluesky has no impressions field"
  end

  test "skips posts synced within MIN_REFRESH_INTERVAL" do
    fresh = posted!(@x_acct, "x", "FRESH")
    fresh.update_columns(metrics_synced_at: 10.minutes.ago, likes: 100)

    X::UserClient.http_stub = ->(*) { raise "should not be called for fresh row" }
    RefreshSocialMetricsJob.new.perform
    assert_equal 100, fresh.reload.likes, "fresh row should be untouched"
  end

  test "skips posts older than REFRESH_WINDOW" do
    old = posted!(@x_acct, "x", "OLD")
    old.update_columns(posted_at: 40.days.ago, metrics_synced_at: nil)

    X::UserClient.http_stub = ->(*) { raise "should not be called for old row" }
    RefreshSocialMetricsJob.new.perform
    assert_nil old.reload.metrics_synced_at, "old row should not be touched"
  end

  test "force: true bypasses MIN_REFRESH_INTERVAL" do
    fresh = posted!(@x_acct, "x", "FRESH-FORCE")
    fresh.update_columns(metrics_synced_at: 5.minutes.ago, likes: 1)
    X::UserClient.http_stub = ->(*) { { status: "200", body: { "data" => { "public_metrics" => { "like_count" => 99 } } } } }

    count = RefreshSocialMetricsJob.new.perform(workspace_id: @ws.id, force: true)
    assert_equal 1, count
    assert_equal 99, fresh.reload.likes
  end

  test "workspace_id: scopes refresh to one workspace" do
    other_owner = User.create!(email_address: "rsm-o-#{SecureRandom.hex(4)}@example.com")
    other_ws    = Workspace.create!(name: "Other", owner: other_owner)
    other_acct  = other_ws.social_accounts.create!(platform: "x", connected_by: other_owner, handle: "@b", external_id: "9",
      access_token: "AT", refresh_token: "RT", token_expires_at: 2.hours.from_now, status: "active")
    mine  = posted!(@x_acct, "x", "MINE")
    other = other_ws.workspace_posts.create!(author: other_owner, social_account: other_acct, platform: "x",
      body: "x", status: "posted", remote_id: "OTHER", posted_at: 1.hour.ago)

    seen = []
    X::UserClient.http_stub = ->(_m, url, _p, _b) {
      seen << url
      { status: "200", body: { "data" => { "public_metrics" => { "like_count" => 1 } } } }
    }

    RefreshSocialMetricsJob.new.perform(workspace_id: @ws.id)
    assert seen.any? { |u| u.include?("MINE") }
    refute seen.any? { |u| u.include?("OTHER") }, "should not touch posts outside the scoped workspace"
  end

  test "one bad fetch doesn't block the rest" do
    bad  = posted!(@x_acct, "x", "BAD")
    good = posted!(@x_acct, "x", "GOOD")

    X::UserClient.http_stub = ->(method, url, _p, _b) {
      raise "boom" if url.include?("BAD")
      { status: "200", body: { "data" => { "public_metrics" => { "like_count" => 7 } } } }
    }

    RefreshSocialMetricsJob.new.perform
    assert_equal 7, good.reload.likes, "good row should be updated"
    assert_nil bad.reload.metrics_synced_at, "bad row left alone"
  end

  private

  test "pushes an engagement alert to workspace members when metrics rise after a prior sync" do
    member = User.create!(email_address: "rsm-mem-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: member, role: "editor")
    post = posted!(@x_acct, "x", "TID-9")
    post.update!(likes: 10, replies: 1, metrics_synced_at: 2.hours.ago) # prior baseline

    X::UserClient.http_stub = ->(_method, url, _payload, _bearer) {
      assert url.include?("TID-9")
      { status: "200", body: { "data" => { "id" => "TID-9", "public_metrics" => {
        "impression_count" => 0, "like_count" => 12, "retweet_count" => 0,
        "reply_count" => 3, "quote_count" => 0, "bookmark_count" => 0
      } } } }
    }

    RefreshSocialMetricsJob.new.perform(workspace_id: @ws.id)

    note = Notification.where(source: "social_engagement", user_id: member.id).order(:created_at).last
    assert note, "the workspace member should receive an engagement push"
    assert_match(/\+2 likes/,   note.title) # 10 -> 12
    assert_match(/\+2 replies/, note.title) # 1 -> 3
    assert_match(/X post/,      note.title)
  end

  test "does not push on a post's first sync (no prior baseline to diff against)" do
    member = User.create!(email_address: "rsm-mem-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: member, role: "editor")
    posted!(@x_acct, "x", "TID-FIRST") # metrics_synced_at is nil

    X::UserClient.http_stub = ->(_method, _url, _payload, _bearer) {
      { status: "200", body: { "data" => { "id" => "TID-FIRST", "public_metrics" => {
        "impression_count" => 0, "like_count" => 50, "retweet_count" => 0,
        "reply_count" => 0, "quote_count" => 0, "bookmark_count" => 0
      } } } }
    }

    assert_no_difference -> { Notification.where(source: "social_engagement").count } do
      RefreshSocialMetricsJob.new.perform(workspace_id: @ws.id)
    end
  end

  test "does not push when metrics are unchanged since the last sync" do
    member = User.create!(email_address: "rsm-mem-#{SecureRandom.hex(4)}@example.com")
    @ws.memberships.create!(user: member, role: "editor")
    post = posted!(@x_acct, "x", "TID-SAME")
    post.update!(likes: 7, metrics_synced_at: 2.hours.ago)

    X::UserClient.http_stub = ->(_method, _url, _payload, _bearer) {
      { status: "200", body: { "data" => { "id" => "TID-SAME", "public_metrics" => {
        "impression_count" => 0, "like_count" => 7, "retweet_count" => 0,
        "reply_count" => 0, "quote_count" => 0, "bookmark_count" => 0
      } } } }
    }

    assert_no_difference -> { Notification.where(source: "social_engagement").count } do
      RefreshSocialMetricsJob.new.perform(workspace_id: @ws.id)
    end
  end

  def posted!(account, platform, remote_id)
    @ws.workspace_posts.create!(
      author: @owner, social_account: account, platform: platform,
      body: "body", status: "posted", remote_id: remote_id, posted_at: 1.hour.ago
    )
  end
end
