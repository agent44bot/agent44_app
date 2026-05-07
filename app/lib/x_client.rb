require "net/http"
require "uri"
require "json"
require "openssl"
require "base64"
require "securerandom"

# Tiny X (Twitter) v2 client. Hand-rolls OAuth 1.0a User Context against
# POST https://api.x.com/2/tweets. We post on behalf of @agent44bot using the
# four credentials stored as fly secrets — there's no per-user OAuth flow.
class XClient
  ENDPOINT = "https://api.x.com/2/tweets"
  MAX_TWEET_LENGTH = 280

  Result = Struct.new(:ok?, :tweet_id, :error, keyword_init: true)

  def self.post_tweet(text)
    new.post_tweet(text)
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
    request["Authorization"] = build_auth_header(uri)
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

  private

  def missing_credentials?
    [@consumer_key, @consumer_secret, @access_token, @access_token_secret].any?(&:blank?)
  end

  # OAuth 1.0a HMAC-SHA1 signature. Tweet body is JSON, so it does NOT
  # contribute to the signature base string — only oauth_* params do.
  def build_auth_header(uri)
    params = {
      oauth_consumer_key:     @consumer_key,
      oauth_nonce:            SecureRandom.hex(16),
      oauth_signature_method: "HMAC-SHA1",
      oauth_timestamp:        Time.now.to_i.to_s,
      oauth_token:            @access_token,
      oauth_version:          "1.0"
    }

    base = [
      "POST",
      percent_encode("#{uri.scheme}://#{uri.host}#{uri.path}"),
      percent_encode(params.sort.map { |k, v| "#{percent_encode(k)}=#{percent_encode(v)}" }.join("&"))
    ].join("&")

    signing_key = "#{percent_encode(@consumer_secret)}&#{percent_encode(@access_token_secret)}"
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", signing_key, base))
    params[:oauth_signature] = signature

    "OAuth " + params.sort.map { |k, v| "#{percent_encode(k)}=\"#{percent_encode(v)}\"" }.join(", ")
  end

  def percent_encode(str)
    URI.encode_www_form_component(str.to_s).gsub("+", "%20")
  end
end
