require "net/http"
require "uri"
require "json"
require "securerandom"

# Per-account X v2 client. Reads bearer token from a SocialAccount row,
# refreshes once on 401, and returns a Result.
module X
  class UserClient
    POST_URL   = "https://api.x.com/2/tweets"
    TWEET_URL  = "https://api.x.com/2/tweets" # /:id appended at call site
    MEDIA_URL  = "https://api.x.com/2/media/upload"
    MAX_TWEET_LENGTH = 280
    TCO_URL_LENGTH   = 23 # X wraps every link in a t.co shortlink of this fixed length
    URL_RE           = %r{https?://\S+}
    # X allows up to 5MB for a tweet image. We guard here so an oversized
    # upload fails fast with a clear message instead of a confusing API error.
    MAX_IMAGE_BYTES  = 5 * 1024 * 1024

    Result      = Struct.new(:ok?, :tweet_id, :error, keyword_init: true)
    MediaResult = Struct.new(:ok?, :media_id, :error, keyword_init: true)

    # Length the way X counts it: every link is 23 chars regardless of its real
    # length, so a long reservation URL doesn't push an otherwise-fine tweet over.
    def self.tweet_length(text)
      text.to_s.gsub(URL_RE) { "x" * TCO_URL_LENGTH }.length
    end

    class << self
      # Stub signature: ->(method, url, payload_or_nil, bearer) -> { status:, body: }
      attr_accessor :http_stub
      # Stub signature: ->(fields_hash, bearer) -> { status:, body: }
      # fields_hash mixes scalars with a file part { filename:, content_type:, data: }.
      attr_accessor :media_stub
    end

    def initialize(social_account)
      @account = social_account
    end

    def post_tweet(text, media_ids: [])
      return Result.new(ok?: false, error: "Account is not X")               unless @account.platform == "x"
      return Result.new(ok?: false, error: "Account needs reauth")           if @account.status != "active"
      return Result.new(ok?: false, error: "Tweet is empty")                 if text.to_s.strip.empty?
      return Result.new(ok?: false, error: "Tweet exceeds #{MAX_TWEET_LENGTH} chars") if self.class.tweet_length(text) > MAX_TWEET_LENGTH

      payload = { text: text }
      payload[:media] = { media_ids: Array(media_ids).map(&:to_s) } if Array(media_ids).any?

      ensure_fresh_token!
      response = http_request(:post, POST_URL, payload: payload)

      if response[:status] == "401"
        return Result.new(ok?: false, error: "Unauthorized — refresh failed") unless refresh_token!
        response = http_request(:post, POST_URL, payload: payload)
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

    # Uploads an image to X and returns a MediaResult with the media_id to
    # attach to a tweet. X's v2 /2/media/upload for images is a SINGLE
    # multipart request (NOT the chunked INIT/APPEND/FINALIZE flow): two form
    # fields, the raw bytes as "media" and "media_category" = "tweet_image"
    # (lowercase; enum is [tweet_image, dm_image, subtitles]). The media_id is
    # at data.id. Requires the media.write OAuth scope (see
    # X::Oauth::DEFAULT_SCOPES); an account connected before that scope was
    # added gets a 403 here until it is reconnected.
    def upload_media(bytes, content_type)
      return MediaResult.new(ok?: false, error: "Account is not X")     unless @account.platform == "x"
      return MediaResult.new(ok?: false, error: "Account needs reauth") if @account.status != "active"
      return MediaResult.new(ok?: false, error: "Empty image")          if bytes.to_s.empty?
      return MediaResult.new(ok?: false, error: "Image exceeds 5MB")     if bytes.bytesize > MAX_IMAGE_BYTES

      ensure_fresh_token!

      fields = {
        "media_category" => "tweet_image",
        "media"          => { filename: "image", content_type: content_type.to_s, data: bytes }
      }
      res = media_request(fields)
      res = media_request(fields) if res[:status] == "401" && refresh_token!

      media_id = res[:body].dig("data", "id")
      return MediaResult.new(ok?: false, error: "image upload: #{format_error(res)}") if media_id.blank?

      MediaResult.new(ok?: true, media_id: media_id)
    rescue => e
      MediaResult.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    # Fetches public engagement metrics for a tweet via /2/tweets/:id with
    # tweet.fields=public_metrics. Returns a hash or nil on failure (the
    # refresh job is best-effort; we just skip and try again next hour).
    def fetch_metrics(tweet_id)
      return nil if tweet_id.to_s.strip.empty?
      ensure_fresh_token!

      url = "https://api.x.com/2/tweets/#{tweet_id}?tweet.fields=public_metrics"
      response = http_request(:get, url)

      if response[:status] == "401"
        return nil unless refresh_token!
        response = http_request(:get, url)
      end

      return nil unless response[:status] == "200"
      m = response[:body].dig("data", "public_metrics") || {}
      {
        impressions: m["impression_count"].to_i,
        likes:       m["like_count"].to_i,
        reposts:     m["retweet_count"].to_i,
        replies:     m["reply_count"].to_i,
        quotes:      m["quote_count"].to_i,
        bookmarks:   m["bookmark_count"].to_i
      }
    rescue => e
      Rails.logger.warn("X fetch_metrics failed for #{tweet_id}: #{e.class}: #{e.message}")
      nil
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
        # Only force a reconnect on a real auth rejection; a transient X 5xx /
        # rate limit / network blip leaves the account active so the scheduled
        # refresh job can recover it without manual reconnect.
        Rails.logger.warn("X refresh failed for SocialAccount ##{@account.id}: #{result.error}")
        @account.mark_needs_reauth! unless result.retryable?
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
        when :get    then Net::HTTP::Get.new(uri)
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

    # POST multipart/form-data to /2/media/upload. `fields` mixes scalar form
    # fields (e.g. "media_category") with a file part ({ filename:,
    # content_type:, data: }, e.g. "media"). Returns { status:, body: }.
    def media_request(fields)
      if self.class.media_stub
        return self.class.media_stub.call(fields, @account.access_token)
      end
      uri      = URI(MEDIA_URL)
      boundary = "----agent44#{SecureRandom.hex(16)}"
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{@account.access_token}"
      req["Content-Type"]  = "multipart/form-data; boundary=#{boundary}"
      req.body = build_multipart_body(fields, boundary)

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
      parsed = begin
        JSON.parse(res.body.to_s)
      rescue JSON::ParserError
        {}
      end
      { status: res.code, body: parsed }
    end

    def build_multipart_body(fields, boundary)
      parts = +""
      fields.each do |name, value|
        parts << "--#{boundary}\r\n"
        if value.is_a?(Hash)
          parts << %(Content-Disposition: form-data; name="#{name}"; filename="#{value[:filename]}"\r\n)
          parts << "Content-Type: #{value[:content_type]}\r\n\r\n"
          parts << value[:data].dup.force_encoding("BINARY")
          parts << "\r\n"
        else
          parts << %(Content-Disposition: form-data; name="#{name}"\r\n\r\n)
          parts << "#{value}\r\n"
        end
      end
      parts << "--#{boundary}--\r\n"
      parts.force_encoding("BINARY")
    end

    def format_error(response)
      body = response[:body] || {}
      msg  = body["detail"] || body["title"] || body["error_description"] || body.dig("errors", 0, "message")
      "HTTP #{response[:status]}#{msg ? ": #{msg}" : ""}"
    end
  end
end
