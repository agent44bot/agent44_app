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
    # X allows up to 5MB for a tweet image. We guard here so an oversized
    # upload fails fast with a clear message instead of a confusing API error.
    MAX_IMAGE_BYTES  = 5 * 1024 * 1024

    Result      = Struct.new(:ok?, :tweet_id, :error, keyword_init: true)
    MediaResult = Struct.new(:ok?, :media_id, :error, keyword_init: true)

    class << self
      # Stub signature: ->(method, url, payload_or_nil, bearer) -> { status:, body: }
      attr_accessor :http_stub
      # Stub signature: ->(params_hash, file_or_nil, bearer) -> { status:, body: }
      # file_or_nil is { filename:, content_type:, data: } on APPEND, else nil.
      attr_accessor :media_stub
    end

    def initialize(social_account)
      @account = social_account
    end

    def post_tweet(text, media_ids: [])
      return Result.new(ok?: false, error: "Account is not X")               unless @account.platform == "x"
      return Result.new(ok?: false, error: "Account needs reauth")           if @account.status != "active"
      return Result.new(ok?: false, error: "Tweet is empty")                 if text.to_s.strip.empty?
      return Result.new(ok?: false, error: "Tweet exceeds #{MAX_TWEET_LENGTH} chars") if text.length > MAX_TWEET_LENGTH

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

    # Uploads an image to X via the v2 chunked flow (INIT -> APPEND -> FINALIZE)
    # and returns a MediaResult carrying the media_id to attach to a tweet.
    # Requires the media.write OAuth scope (see X::Oauth::DEFAULT_SCOPES); an
    # account connected before that scope was added gets a 403 here until it is
    # reconnected. Images finalize synchronously, so no STATUS polling.
    #
    # IMPORTANT: the command parameters (command/total_bytes/media_type/etc.)
    # go in the QUERY STRING, not the request body. X returns HTTP 400 if they
    # are sent as form fields. Only APPEND has a body, and only the raw image
    # bytes as a multipart "media" part. (Matches X's official xurl examples.)
    def upload_media(bytes, content_type)
      return MediaResult.new(ok?: false, error: "Account is not X")     unless @account.platform == "x"
      return MediaResult.new(ok?: false, error: "Account needs reauth") if @account.status != "active"
      return MediaResult.new(ok?: false, error: "Empty image")          if bytes.to_s.empty?
      return MediaResult.new(ok?: false, error: "Image exceeds 5MB")     if bytes.bytesize > MAX_IMAGE_BYTES

      ensure_fresh_token!

      init_params = { command: "INIT", total_bytes: bytes.bytesize, media_type: content_type.to_s, media_category: "tweet_image" }
      init = media_request(init_params)
      init = media_request(init_params) if init[:status] == "401" && refresh_token!
      media_id = init[:body].dig("data", "id")
      return MediaResult.new(ok?: false, error: "INIT failed: #{format_error(init)}") if media_id.blank?

      append = media_request(
        { command: "APPEND", media_id: media_id, segment_index: 0 },
        file: { filename: "image", content_type: content_type.to_s, data: bytes }
      )
      unless %w[200 204].include?(append[:status])
        return MediaResult.new(ok?: false, error: "APPEND failed: #{format_error(append)}")
      end

      final = media_request({ command: "FINALIZE", media_id: media_id })
      unless %w[200 201].include?(final[:status])
        return MediaResult.new(ok?: false, error: "FINALIZE failed: #{format_error(final)}")
      end

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

    # POST to /2/media/upload. The command params go in the QUERY STRING; a
    # body is sent only when `file` is given (APPEND), as a single multipart
    # "media" part carrying the raw bytes. Returns { status:, body: }.
    def media_request(params, file: nil)
      if self.class.media_stub
        return self.class.media_stub.call(params, file, @account.access_token)
      end
      uri = URI("#{MEDIA_URL}?#{URI.encode_www_form(params)}")
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{@account.access_token}"

      if file
        boundary = "----agent44#{SecureRandom.hex(16)}"
        req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        req.body = build_multipart_body({ "media" => file }, boundary)
      end

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
