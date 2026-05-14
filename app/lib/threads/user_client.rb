require "net/http"
require "uri"
require "json"

# Per-account Threads client. Threads has a two-step publish flow: first
# create a media container, then publish it. For text-only posts the
# container is processed instantly; we don't need to poll status.
module Threads
  class UserClient
    GRAPH_URL  = "https://graph.threads.net/v1.0"
    MAX_LENGTH = 500  # Threads' post length cap

    Result = Struct.new(:ok?, :post_id, :permalink_url, :error, keyword_init: true)

    class << self
      # Stub signature: ->(method, url, params|nil, bearer_or_nil) -> { status:, body: }
      attr_accessor :http_stub
    end

    def initialize(social_account)
      @account = social_account
    end

    def post_text(text)
      return Result.new(ok?: false, error: "Account is not Threads")             unless @account.platform == "threads"
      return Result.new(ok?: false, error: "Account needs reauth")               if @account.status != "active"
      return Result.new(ok?: false, error: "Post is empty")                      if text.to_s.strip.empty?
      return Result.new(ok?: false, error: "Post exceeds #{MAX_LENGTH} chars")   if text.length > MAX_LENGTH

      ensure_fresh_token!

      # Step 1: create container
      create_resp = http_request(:post, "#{GRAPH_URL}/#{@account.external_id}/threads", params: {
        media_type:   "TEXT",
        text:         text,
        access_token: @account.access_token
      })

      if create_resp[:status] == "401"
        return Result.new(ok?: false, error: "Unauthorized — refresh failed") unless refresh_token!
        create_resp = http_request(:post, "#{GRAPH_URL}/#{@account.external_id}/threads", params: {
          media_type: "TEXT", text: text, access_token: @account.access_token
        })
      end

      return Result.new(ok?: false, error: "Container create: #{format_error(create_resp)}") unless create_resp[:status] == "200"
      container_id = create_resp[:body]["id"]
      return Result.new(ok?: false, error: "Container create returned no id") if container_id.blank?

      # Step 2: publish
      publish_resp = http_request(:post, "#{GRAPH_URL}/#{@account.external_id}/threads_publish", params: {
        creation_id:  container_id,
        access_token: @account.access_token
      })
      return Result.new(ok?: false, error: "Publish: #{format_error(publish_resp)}") unless publish_resp[:status] == "200"

      post_id = publish_resp[:body]["id"]
      permalink = fetch_permalink(post_id)
      Result.new(ok?: true, post_id: post_id, permalink_url: permalink)
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    def delete_post(post_id)
      return Result.new(ok?: false, error: "Account is not Threads") unless @account.platform == "threads"
      return Result.new(ok?: false, error: "Missing post id")        if post_id.to_s.strip.empty?

      ensure_fresh_token!
      response = http_request(:delete, "#{GRAPH_URL}/#{post_id}", params: { access_token: @account.access_token })

      case response[:status]
      when "200"
        Result.new(ok?: true, post_id: post_id)
      when "404"
        Result.new(ok?: true, post_id: post_id) # already gone
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

    def fetch_permalink(post_id)
      resp = http_request(:get, "#{GRAPH_URL}/#{post_id}", params: {
        fields:       "permalink",
        access_token: @account.access_token
      })
      resp[:status] == "200" ? resp[:body]["permalink"] : nil
    end

    def ensure_fresh_token!
      return if @account.token_expires_at.nil?
      return if @account.token_expires_at > 1.day.from_now
      refresh_token!
    end

    def refresh_token!
      result = ::Threads::Oauth.refresh(long_token: @account.access_token)
      if result.ok?
        @account.update!(
          access_token:     result.access_token,
          token_expires_at: result.expires_in ? Time.current + result.expires_in.to_i.seconds : nil,
          status:           "active",
          last_synced_at:   Time.current
        )
        true
      else
        Rails.logger.warn("Threads refresh failed for SocialAccount ##{@account.id}: #{result.error}")
        @account.mark_needs_reauth!
        false
      end
    end

    def http_request(method, url, params: {})
      if self.class.http_stub
        return self.class.http_stub.call(method, url, params, @account.access_token)
      end
      uri = URI(url)
      uri.query = URI.encode_www_form(params) if params.any? && method != :post
      req =
        case method
        when :post   then Net::HTTP::Post.new(uri).tap   { |r| r.body = URI.encode_www_form(params); r["Content-Type"] = "application/x-www-form-urlencoded" }
        when :delete then Net::HTTP::Delete.new(uri)
        when :get    then Net::HTTP::Get.new(uri)
        else raise ArgumentError, "unsupported method #{method}"
        end
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
      msg  = body.dig("error", "message") || body["error_description"] || body["error"]
      "HTTP #{response[:status]}#{msg ? ": #{msg}" : ""}"
    end
  end
end
