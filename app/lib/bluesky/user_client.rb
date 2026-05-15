require "net/http"
require "uri"
require "json"

# Per-account Bluesky client. Same shape as X::UserClient: posts via the
# stored accessJwt, refreshes once on 401 using the refreshJwt, returns a
# Result struct.
module Bluesky
  class UserClient
    PDS_URL              = "https://bsky.social"
    CREATE_RECORD_PATH   = "/xrpc/com.atproto.repo.createRecord"
    DELETE_RECORD_PATH   = "/xrpc/com.atproto.repo.deleteRecord"
    FEED_COLLECTION      = "app.bsky.feed.post"
    MAX_LENGTH           = 300  # Bluesky's post length limit

    Result = Struct.new(:ok?, :post_id, :uri, :error, keyword_init: true)

    class << self
      # Stub signature: ->(method, url, payload, bearer) -> { status:, body: }
      attr_accessor :http_stub
    end

    def initialize(social_account)
      @account = social_account
    end

    def post_text(text)
      return Result.new(ok?: false, error: "Account is not Bluesky") unless @account.platform == "bluesky"
      return Result.new(ok?: false, error: "Account needs reauth")   if @account.status != "active"
      return Result.new(ok?: false, error: "Post is empty")          if text.to_s.strip.empty?
      return Result.new(ok?: false, error: "Post exceeds #{MAX_LENGTH} chars") if text.length > MAX_LENGTH

      ensure_fresh_token!
      payload = {
        repo:       @account.external_id,
        collection: FEED_COLLECTION,
        record: {
          text:      text,
          createdAt: Time.current.utc.iso8601
        }
      }
      response = http_request(:post, PDS_URL + CREATE_RECORD_PATH, payload: payload)

      if response[:status] == "401"
        return Result.new(ok?: false, error: "Unauthorized — refresh failed") unless refresh_token!
        response = http_request(:post, PDS_URL + CREATE_RECORD_PATH, payload: payload)
      end

      case response[:status]
      when "200"
        at_uri  = response[:body]["uri"]                     # at://did:plc:.../app.bsky.feed.post/<rkey>
        post_id = at_uri.to_s.split("/").last
        Result.new(ok?: true, post_id: post_id, uri: at_uri)
      when "401"
        @account.mark_needs_reauth!
        Result.new(ok?: false, error: "Unauthorized (account needs reauth)")
      else
        Result.new(ok?: false, error: format_error(response))
      end
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    def delete_post(post_id)
      return Result.new(ok?: false, error: "Account is not Bluesky") unless @account.platform == "bluesky"
      return Result.new(ok?: false, error: "Missing post id")        if post_id.to_s.strip.empty?

      ensure_fresh_token!
      payload = {
        repo:       @account.external_id,
        collection: FEED_COLLECTION,
        rkey:       post_id
      }
      response = http_request(:post, PDS_URL + DELETE_RECORD_PATH, payload: payload)

      if response[:status] == "401"
        return Result.new(ok?: false, error: "Unauthorized — refresh failed") unless refresh_token!
        response = http_request(:post, PDS_URL + DELETE_RECORD_PATH, payload: payload)
      end

      case response[:status]
      when "200"
        Result.new(ok?: true, post_id: post_id)
      when "400"
        # Bluesky returns 400 with InvalidSwap when the record is already gone.
        msg = response[:body]["message"].to_s
        if msg.include?("Could not locate") || msg.include?("not found") || response[:body]["error"] == "InvalidSwap"
          Result.new(ok?: true, post_id: post_id)
        else
          Result.new(ok?: false, error: format_error(response))
        end
      when "401"
        @account.mark_needs_reauth!
        Result.new(ok?: false, error: "Unauthorized (account needs reauth)")
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
      result = ::Bluesky::Session.refresh(refresh_jwt: @account.refresh_token)
      if result.ok?
        @account.update!(
          access_token:     result.access_jwt,
          refresh_token:    result.refresh_jwt,
          token_expires_at: ::Bluesky::Session::DEFAULT_EXPIRES.from_now,
          status:           "active",
          last_synced_at:   Time.current
        )
        true
      else
        Rails.logger.warn("Bluesky refresh failed for SocialAccount ##{@account.id}: #{result.error}")
        @account.mark_needs_reauth!
        false
      end
    end

    def http_request(method, url, payload: nil)
      if self.class.http_stub
        return self.class.http_stub.call(method, url, payload, @account.access_token)
      end
      uri = URI(url)
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{@account.access_token}"
      req["Content-Type"]  = "application/json"
      req.body = payload.to_json if payload
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
      body = begin
        JSON.parse(res.body.to_s)
      rescue JSON::ParserError
        {}
      end
      { status: res.code, body: body }
    end

    def format_error(response)
      body = response[:body] || {}
      msg  = body["message"] || body["error"]
      "HTTP #{response[:status]}#{msg ? ": #{msg}" : ""}"
    end
  end
end
