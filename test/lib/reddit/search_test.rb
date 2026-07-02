require "test_helper"

class RedditSearchTest < ActiveSupport::TestCase
  teardown { Reddit::Search.http_stub = nil }

  test "parses posts into the common candidate shape" do
    Reddit::Search.http_stub = lambda do |_url|
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
    Reddit::Search.http_stub = ->(_url) { called = true; nil }
    assert_equal [], Reddit::Search.posts("")
    assert_not called
  end

  test "a nil/failed fetch yields no posts" do
    Reddit::Search.http_stub = ->(_url) { nil }
    assert_equal [], Reddit::Search.posts("cooking", subreddits: %w[Rochester])
  end
end
