require "test_helper"

class RedditAuthTest < ActiveSupport::TestCase
  teardown do
    Reddit::Auth.token_stub = nil
    Rails.cache.delete(Reddit::Auth::CACHE_KEY)
    ENV.delete("REDDIT_CLIENT_ID"); ENV.delete("REDDIT_CLIENT_SECRET")
  end

  test "returns nil (and stays unconfigured) with no credentials" do
    assert_not Reddit::Auth.configured?
    assert_nil Reddit::Auth.token
  end

  test "fetches an app-only token from the client_credentials grant when configured" do
    ENV["REDDIT_CLIENT_ID"] = "id"; ENV["REDDIT_CLIENT_SECRET"] = "secret"
    Reddit::Auth.token_stub = lambda do |id, secret|
      assert_equal "id", id
      assert_equal "secret", secret
      "TOKEN"
    end
    assert Reddit::Auth.configured?
    assert_equal "TOKEN", Reddit::Auth.token
  end
end
