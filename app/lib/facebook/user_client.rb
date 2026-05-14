require "net/http"
require "uri"
require "json"

# Per-Page Facebook client. Posts to /{page-id}/feed using the stored
# Page access token. Page tokens don't expire on a normal cadence (they
# stay valid as long as the underlying user token + permissions hold),
# so there's no refresh step here — if the token goes invalid, we mark
# the account needs_reauth and the workspace admin re-runs Connect.
module Facebook
  class UserClient
    GRAPH_URL  = "https://graph.facebook.com/v21.0"
    MAX_LENGTH = 63206  # Facebook's text limit. Effectively unlimited for our case.

    Result = Struct.new(:ok?, :post_id, :permalink_url, :error, keyword_init: true)

    class << self
      # Stub signature: ->(method, url, params|nil, bearer) -> { status:, body: }
      attr_accessor :http_stub
    end

    def initialize(social_account)
      @account = social_account
    end

    def post_text(text)
      return Result.new(ok?: false, error: "Account is not Facebook") unless @account.platform == "facebook"
      return Result.new(ok?: false, error: "Account needs reauth")    if @account.status != "active"
      return Result.new(ok?: false, error: "Post is empty")           if text.to_s.strip.empty?

      response = http_request(:post, "#{GRAPH_URL}/#{@account.external_id}/feed", params: {
        message:      text,
        access_token: @account.access_token
      })

      case response[:status]
      when "200"
        full_id = response[:body]["id"].to_s        # "<page-id>_<post-id>"
        post_id = full_id.split("_").last
        permalink = "https://www.facebook.com/#{@account.external_id}/posts/#{post_id}"
        Result.new(ok?: true, post_id: full_id, permalink_url: permalink)
      when "401", "190"
        @account.mark_needs_reauth!
        Result.new(ok?: false, error: "Unauthorized (account needs reauth)")
      else
        Result.new(ok?: false, error: format_error(response))
      end
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    def delete_post(full_post_id)
      return Result.new(ok?: false, error: "Account is not Facebook") unless @account.platform == "facebook"
      return Result.new(ok?: false, error: "Missing post id")         if full_post_id.to_s.strip.empty?

      response = http_request(:delete, "#{GRAPH_URL}/#{full_post_id}", params: { access_token: @account.access_token })

      case response[:status]
      when "200"
        Result.new(ok?: true, post_id: full_post_id)
      when "404"
        Result.new(ok?: true, post_id: full_post_id) # already gone
      when "401", "190"
        @account.mark_needs_reauth!
        Result.new(ok?: false, error: "Unauthorized (account needs reauth)")
      else
        Result.new(ok?: false, error: format_error(response))
      end
    rescue => e
      Result.new(ok?: false, error: "#{e.class}: #{e.message}")
    end

    private

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
        else raise ArgumentError, "unsupported method #{method}"
        end
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
      body = JSON.parse(res.body.to_s) rescue {}
      { status: res.code, body: body }
    end

    def format_error(response)
      body = response[:body] || {}
      msg  = body.dig("error", "message") || body["error_description"] || body["error"]
      "HTTP #{response[:status]}#{msg ? ": #{msg}" : ""}"
    end
  end
end
