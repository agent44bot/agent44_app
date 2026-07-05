require "test_helper"

class RedditSearchTest < ActiveSupport::TestCase
  teardown do
    Reddit::Search.http_stub = nil
    Reddit::Auth.token_stub = nil
    Rails.cache.delete(Reddit::Auth::CACHE_KEY)
  end

  test "parses posts into the common candidate shape" do
    Reddit::Search.http_stub = lambda do |_url, _bearer|
      { "data" => { "children" => [ { "data" => {
        "name" => "t3_abc", "author" => "rocfoodie", "title" => "Date night?", "selftext" => "cooking class",
        "permalink" => "/r/Rochester/abc", "created_utc" => 1_751_000_000 } } ] } }
    end
    posts = Reddit::Search.posts("cooking", subreddits: %w[Rochester])
    assert_equal 1, posts.size
    p = posts.first
    assert_equal "t3_abc", p[:external_id]
    assert_equal "rocfoodie", p[:author]
    assert_equal "Date night? - cooking class", p[:text]
    assert_equal "https://www.reddit.com/r/Rochester/abc", p[:url]
    assert p[:posted_at].present?
  end

  test "empty query returns [] without calling out" do
    called = false
    Reddit::Search.http_stub = ->(_url, _bearer) { called = true; nil }
    assert_equal [], Reddit::Search.posts("")
    assert_not called
  end

  test "a nil/failed fetch yields no posts" do
    Reddit::Search.http_stub = ->(_url, _bearer) { nil }
    assert_equal [], Reddit::Search.posts("cooking", subreddits: %w[Rochester])
  end

  test "uses the authed oauth host + bearer when Reddit is configured" do
    Reddit::Auth.token_stub = ->(_id, _secret) { "TOKEN123" }
    ENV["REDDIT_CLIENT_ID"] = "id"; ENV["REDDIT_CLIENT_SECRET"] = "secret"
    seen_url = nil; seen_bearer = nil
    Reddit::Search.http_stub = lambda do |url, bearer|
      seen_url = url; seen_bearer = bearer
      { "data" => { "children" => [] } }
    end
    Reddit::Search.posts("cooking", subreddits: %w[Rochester])
    assert_includes seen_url, "https://oauth.reddit.com/r/Rochester/search.json"
    assert_equal "TOKEN123", seen_bearer
  ensure
    ENV.delete("REDDIT_CLIENT_ID"); ENV.delete("REDDIT_CLIENT_SECRET")
  end

  test "falls back to the public host with no bearer when unconfigured" do
    seen_url = nil; seen_bearer = :unset
    Reddit::Search.http_stub = lambda do |url, bearer|
      seen_url = url; seen_bearer = bearer
      { "data" => { "children" => [] } }
    end
    Reddit::Search.posts("cooking", subreddits: %w[Rochester])
    assert_includes seen_url, "https://www.reddit.com/r/Rochester/search.json"
    assert_nil seen_bearer
  end
end
