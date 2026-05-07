require "net/http"
require "uri"
require "json"
require "simple_oauth"

# Tiny X (Twitter) v2 client. We post on behalf of @agent44bot using the
# four OAuth 1.0a credentials stored as fly secrets — no per-user OAuth flow.
class XClient
  ENDPOINT = "https://api.x.com/2/tweets"
  MAX_TWEET_LENGTH = 280

  Result = Struct.new(:ok?, :tweet_id, :error, keyword_init: true)

  def self.post_tweet(text)
    new.post_tweet(text)
  end

  def self.delete_tweet(tweet_id)
    new.delete_tweet(tweet_id)
  end

  def initialize
    @consumer_key        = ENV["X_CONSUMER_KEY"]
    @consumer_secret     = ENV["X_CONSUMER_SECRET"]
    @access_token        = ENV["X_ACCESS_TOKEN"]
    @access_token_secret = ENV["X_ACCESS_TOKEN_SECRET"]
  end

  def post_tweet(text)
    return Result.new(ok?: false, error: "X credentials missing") if missing_credentials?
    return Result.new(ok?: false, error: "Tweet is empty") if text.to_s.strip.empty?
    return Result.new(ok?: false, error: "Tweet exceeds #{MAX_TWEET_LENGTH} chars") if text.length > MAX_TWEET_LENGTH

    uri = URI(ENDPOINT)
    body = { text: text }.to_json

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = oauth_header(uri, :post)
    request.body = body

    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      response = http.request(request)
      payload = JSON.parse(response.body) rescue {}
      if response.code == "201"
        Result.new(ok?: true, tweet_id: payload.dig("data", "id"))
      else
        Result.new(ok?: false, error: "HTTP #{response.code}: #{payload['detail'] || payload['title'] || response.body[0, 200]}")
      end
    end
  rescue => e
    Result.new(ok?: false, error: "#{e.class}: #{e.message}")
  end

  def delete_tweet(tweet_id)
    return Result.new(ok?: false, error: "X credentials missing") if missing_credentials?
    return Result.new(ok?: false, error: "Missing tweet id") if tweet_id.to_s.strip.empty?

    uri = URI("https://api.x.com/2/tweets/#{tweet_id}")

    request = Net::HTTP::Delete.new(uri)
    request["Authorization"] = oauth_header(uri, :delete)

    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      response = http.request(request)
      payload = JSON.parse(response.body) rescue {}
      if response.code == "200" && payload.dig("data", "deleted") == true
        Result.new(ok?: true, tweet_id: tweet_id)
      else
        Result.new(ok?: false, error: "HTTP #{response.code}: #{payload['detail'] || payload['title'] || response.body[0, 200]}")
      end
    end
  rescue => e
    Result.new(ok?: false, error: "#{e.class}: #{e.message}")
  end

  private

  def missing_credentials?
    [@consumer_key, @consumer_secret, @access_token, @access_token_secret].any?(&:blank?)
  end

  def oauth_header(uri, method)
    SimpleOAuth::Header.new(method, uri.to_s, {},
      consumer_key:    @consumer_key,
      consumer_secret: @consumer_secret,
      token:           @access_token,
      token_secret:    @access_token_secret
    ).to_s
  end
end
