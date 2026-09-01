require "test_helper"

# Behind fly's edge proxy, request.remote_ip is the proxy's own address for
# every visitor (see Trackable#client_ip), so Rails' default rate-limit key
# lumps the whole internet into one bucket and unrelated people hand each
# other a 429. Every rate_limit in the app must key on the real client
# address instead.
class RateLimitClientIpTest < ActionDispatch::IntegrationTest
  test "two clients behind the same proxy get separate rate-limit buckets" do
    keys = capture_rate_limit_keys do
      post sign_in_path, params: { email_address: "a@example.com" },
        headers: { "Fly-Client-IP" => "203.0.113.7", "REMOTE_ADDR" => "66.241.125.168" }
      post sign_in_path, params: { email_address: "b@example.com" },
        headers: { "Fly-Client-IP" => "198.51.100.9", "REMOTE_ADDR" => "66.241.125.168" }
    end

    assert_equal 2, keys.size, "expected one rate-limit lookup per request"
    assert_equal 2, keys.uniq.size, "both clients shared a bucket: #{keys.inspect}"
    assert keys.first.end_with?("203.0.113.7"), keys.first
    assert keys.last.end_with?("198.51.100.9"), keys.last
  end

  test "every rate_limit in the app keys on the client ip" do
    offenders = Dir[Rails.root.join("app/controllers/**/*.rb")].flat_map { |path|
      File.readlines(path).each_with_index.filter_map do |line, i|
        next unless line.match?(/^\s*rate_limit /)
        next if line.include?("RATE_LIMIT_BY_CLIENT_IP")
        "#{path.delete_prefix(Rails.root.to_s + '/')}:#{i + 1}"
      end
    }

    assert_empty offenders,
      "these rate limits bucket by fly's proxy address; pass by: RATE_LIMIT_BY_CLIENT_IP"
  end

  private

  # The rate limiter holds the cache store it was given at class-definition
  # time (:null_store in test, so limits never actually trip here). Listening
  # to its #increment is how we see the bucket key each request lands in.
  def capture_rate_limit_keys
    store = ActionController::Base.cache_store
    keys = []
    store.define_singleton_method(:increment) do |name, _amount = 1, **_options|
      keys << name
      nil
    end
    yield
    keys
  ensure
    store.singleton_class.send(:remove_method, :increment)
  end
end
