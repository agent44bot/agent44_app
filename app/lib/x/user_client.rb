require "net/http"
require "uri"
require "json"

# Per-account X v2 client. Reads bearer token from a SocialAccount row,
# refreshes once on 401, and returns a Result.
module X
  class UserClient
    POST_URL  = "https://api.x.com/2/tweets"
    TWEET_URL = "https://api.x.com/2/tweets" # /:id appended at call site
    MAX_TWEET_LENGTH = 280

    Result = Struct.new(:ok?, :tweet_id, :error, keyword_init: true)

    class << self
      # Stub signature: ->(method, url, payload_or_nil, bearer) -> { status:, body: }
      attr_accessor :http_stub
    end

    def initialize(social_account)
      @account = social_account
    end

    def post_tweet(text)
      return Result.new(ok?: false, error: "Account is not X")               unless @account.platform == "x"
      return Result.new(ok?: false, error: "Account needs reauth")           if @account.status != "active"
      return Result.new(ok?: false, error: "Tweet is empty")                 if text.to_s.strip.empty?
      return Result.new(ok?: false, error: "Tweet exceeds #{MAX_TWEET_LENGTH} chars") if text.length > MAX_TWEET_LENGTH

      ensure_fresh_token!
      response = http_request(:post, POST_URL, payload: { text: text })

      if response[:status] == "401"
        return Result.new(ok?: false, error: "Unauthorized — refresh failed") unless refresh_token!
        response = http_request(:post, POST_URL, payload: { text: text })
      end

      case response[:status]
      when "201"
        Result.new(ok?: true, tweet_id: response[:body].dig("data", "id"))
      when "401"
        @account.mark_needs_reauth!
        Result.new(ok?: false, error: "Unauthorized (account needs reauth)")
      else
        Result.new(ok?: false, error: format_error(response))
      end
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    def delete_tweet(tweet_id)
      return Result.new(ok?: false, error: "Account is not X")    unless @account.platform == "x"
      return Result.new(ok?: false, error: "Missing tweet id")    if tweet_id.to_s.strip.empty?

      ensure_fresh_token!
      url = "#{TWEET_URL}/#{tweet_id}"
      response = http_request(:delete, url)

      if response[:status] == "401"
        return Result.new(ok?: false, error: "Unauthorized — refresh failed") unless refresh_token!
        response = http_request(:delete, url)
      end

      case response[:status]
      when "200"
        if response[:body].dig("data", "deleted")
          Result.new(ok?: true, tweet_id: tweet_id)
        else
          Result.new(ok?: false, error: "X returned 200 but deleted=false")
        end
      when "401"
        @account.mark_needs_reauth!
        Result.new(ok?: false, error: "Unauthorized (account needs reauth)")
      when "404"
        # Already gone — treat as success so the row can be removed.
        Result.new(ok?: true, tweet_id: tweet_id)
      else
        Result.new(ok?: false, error: format_error(response))
      end
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    private

    def ensure_fresh_token!
      return if @account.token_expires_at.nil?
      return if @account.token_expires_at > 60.seconds.from_now
      refresh_token!
    end

    def refresh_token!
      return false if @account.refresh_token.blank?
      result = ::X::Oauth.refresh(refresh_token: @account.refresh_token)
      if result.ok?
        @account.update!(
          access_token:     result.access_token,
          refresh_token:    result.refresh_token.presence || @account.refresh_token,
          token_expires_at: result.expires_in ? Time.current + result.expires_in.to_i.seconds : nil,
          scopes:           result.scope.presence || @account.scopes,
          status:           "active",
          last_synced_at:   Time.current
        )
        true
      else
        Rails.logger.warn("X refresh failed for SocialAccount ##{@account.id}: #{result.error}")
        @account.mark_needs_reauth!
        false
      end
    end

    def http_request(method, url, payload: nil)
      if self.class.http_stub
        return self.class.http_stub.call(method, url, payload, @account.access_token)
      end
      uri = URI(url)
      req =
        case method
        when :post   then Net::HTTP::Post.new(uri)
        when :delete then Net::HTTP::Delete.new(uri)
        else raise ArgumentError, "unsupported method #{method}"
        end
      req["Authorization"] = "Bearer #{@account.access_token}"
      if payload
        req["Content-Type"] = "application/json"
        req.body = payload.to_json
      end
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
      body = begin
        JSON.parse(res.body.to_s)
      rescue JSON::ParserError
        {}
      end
      { status: res.code, body: body }
    end

    def format_error(response)
      body = response[:body] || {}
      msg  = body["detail"] || body["title"] || body["error_description"] || body.dig("errors", 0, "message")
      "HTTP #{response[:status]}#{msg ? ": #{msg}" : ""}"
    end
  end
end
