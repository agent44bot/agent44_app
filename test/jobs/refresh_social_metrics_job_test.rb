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

  def posted!(account, platform, remote_id)
    @ws.workspace_posts.create!(
      author: @owner, social_account: account, platform: platform,
      body: "body", status: "posted", remote_id: remote_id, posted_at: 1.hour.ago
    )
  end
end
