require "net/http"
require "uri"
require "json"

# Threads OAuth 2.0 (Meta Graph API). Confidential client + state, no PKCE.
# Token lifecycle:
#   1. exchange_code  - returns SHORT-lived (~1h) access_token + user_id
#   2. exchange_for_long_lived - swaps short for ~60-day long-lived
#   3. refresh - extends a long-lived token before it expires
# We persist the long-lived token in SocialAccount#access_token; there is
# no separate refresh token in this flow (refresh is a "rotate this token"
# call, not a refresh-grant exchange).
module Threads
  class Oauth
    AUTHORIZE_URL    = "https://threads.net/oauth/authorize"
    TOKEN_URL        = "https://graph.threads.net/oauth/access_token"
    LONG_LIVED_URL   = "https://graph.threads.net/access_token"
    REFRESH_URL      = "https://graph.threads.net/refresh_access_token"
    ME_URL           = "https://graph.threads.net/v1.0/me"
    DEFAULT_SCOPES   = %w[threads_basic threads_content_publish threads_delete].freeze

    TokenResult = Struct.new(:ok?, :access_token, :user_id, :expires_in, :error, keyword_init: true)
    UserResult  = Struct.new(:ok?, :id, :username, :name, :error, keyword_init: true)

    class << self
      # Stub signature: ->(method, url, params|payload, headers) -> [status, body_hash]
      attr_accessor :http_stub

      def configured?
        client_id.present? && client_secret.present?
      end

      def client_id
        Rails.application.credentials.dig(:threads, :client_id) || ENV["THREADS_CLIENT_ID"]
      end

      def client_secret
        Rails.application.credentials.dig(:threads, :client_secret) || ENV["THREADS_CLIENT_SECRET"]
      end

      def authorization_url(redirect_uri:, state:, scopes: DEFAULT_SCOPES)
        params = {
          client_id:     client_id,
          redirect_uri:  redirect_uri,
          scope:         scopes.join(","),
          response_type: "code",
          state:         state
        }
        "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
      end

      def exchange_code(code:, redirect_uri:)
        status, body = post_form(TOKEN_URL, {
          client_id:     client_id,
          client_secret: client_secret,
          grant_type:    "authorization_code",
          redirect_uri:  redirect_uri,
          code:          code
        })
        if status == "200" && body["access_token"].present?
          TokenResult.new(ok?: true, access_token: body["access_token"], user_id: body["user_id"], expires_in: 3600)
        else
          TokenResult.new(ok?: false, error: format_error(status, body))
        end
      end

      def exchange_for_long_lived(short_token:)
        status, body = get_json(LONG_LIVED_URL, params: {
          grant_type:    "th_exchange_token",
          client_secret: client_secret,
          access_token:  short_token
        })
        parse_long_lived(status, body)
      end

      def refresh(long_token:)
        status, body = get_json(REFRESH_URL, params: {
          grant_type:   "th_refresh_token",
          access_token: long_token
        })
        parse_long_lived(status, body)
      end

      def me(access_token:)
        status, body = get_json(ME_URL, params: {
          fields:       "id,username,name",
          access_token: access_token
        })
        if status == "200" && body["id"].present?
          UserResult.new(ok?: true, id: body["id"], username: body["username"], name: body["name"])
        else
          UserResult.new(ok?: false, error: format_error(status, body))
        end
      rescue => e
        UserResult.new(ok?: false, error: "#{e.class}: #{e.message}")
      end

      private

      def parse_long_lived(status, body)
        if status == "200" && body["access_token"].present?
          TokenResult.new(ok?: true, access_token: body["access_token"], expires_in: body["expires_in"])
        else
          TokenResult.new(ok?: false, error: format_error(status, body))
        end
      end

      def post_form(url, params)
        return http_stub.call(:post, url, params, nil) if http_stub
        uri = URI(url)
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(params)
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
        [res.code, parse_json(res.body)]
      end

      def get_json(url, params: {})
        return http_stub.call(:get, url, params, nil) if http_stub
        uri = URI(url)
        uri.query = URI.encode_www_form(params) if params.any?
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(Net::HTTP::Get.new(uri)) }
        [res.code, parse_json(res.body)]
      end

      def parse_json(body)
        JSON.parse(body.to_s)
      rescue JSON::ParserError
        {}
      end

      def format_error(status, body)
        body ||= {}
        msg = body.dig("error", "message") || body["error_description"] || body["error"] || body["message"]
        "HTTP #{status}#{msg ? ": #{msg}" : ""}"
      end
    end
  end
end
