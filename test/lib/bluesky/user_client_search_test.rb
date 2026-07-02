require "test_helper"

class BlueskyUserClientSearchTest < ActiveSupport::TestCase
  setup do
    owner = User.create!(email_address: "bs-#{SecureRandom.hex(4)}@example.com")
    ws = Workspace.create!(name: "BS WS", slug: "bs-#{SecureRandom.hex(4)}", owner: owner)
    @account = ws.social_accounts.create!(platform: "bluesky", connected_by: owner, handle: "@nyk.bsky.social",
                                          external_id: "did:plc:x", access_token: "AT", refresh_token: "RT",
                                          token_expires_at: 2.hours.from_now, status: "active")
  end

  teardown { Bluesky::UserClient.http_stub = nil }

  test "search_posts parses matching posts and drops empty-text ones" do
    captured = nil
    Bluesky::UserClient.http_stub = lambda do |_method, url, _payload, _bearer|
      captured = url
      { status: "200", body: { "posts" => [
        { "uri" => "at://did:plc:foodie/app.bsky.feed.post/1", "author" => { "handle" => "foodie.bsky.social" },
          "record" => { "text" => "cooking class?" }, "indexedAt" => "2026-07-02T12:00:00Z" },
        { "uri" => "at://x/app.bsky.feed.post/2", "author" => { "handle" => "x.bsky.social" },
          "record" => { "text" => "" } } ] } }
    end
    posts = Bluesky::UserClient.new(@account).search_posts("cooking class")
    assert_includes captured, "searchPosts"
    assert_equal 1, posts.size
    p = posts.first
    assert_equal "at://did:plc:foodie/app.bsky.feed.post/1", p[:external_id]
    assert_equal "foodie.bsky.social", p[:author]
    assert_equal "https://bsky.app/profile/foodie.bsky.social/post/1", p[:url]
    assert p[:posted_at].present?
  end

  test "empty query returns [] without a call" do
    called = false
    Bluesky::UserClient.http_stub = ->(*) { called = true; { status: "200", body: {} } }
    assert_equal [], Bluesky::UserClient.new(@account).search_posts("")
    assert_not called
  end

  test "a non-200 yields no posts" do
    Bluesky::UserClient.http_stub = ->(*) { { status: "500", body: {} } }
    assert_equal [], Bluesky::UserClient.new(@account).search_posts("cooking")
  end
end
