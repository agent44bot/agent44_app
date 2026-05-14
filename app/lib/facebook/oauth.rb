require "net/http"
require "uri"
require "json"

# Facebook Pages OAuth via Meta Graph API. Same family as Threads OAuth
# but the post target is a Page, not the user. Flow:
#   1. authorize  - user grants pages_manage_posts/pages_show_list/pages_read_engagement
#   2. exchange_code - returns SHORT-lived user access token
#   3. exchange_for_long_lived_user - swaps for ~60-day user token
#   4. pages - lists Pages the user manages (each row has a long-lived
#              page-scoped access token that effectively never expires
#              unless the user revokes)
# We persist the page_id as external_id and the page access token as
# access_token. No refresh needed for a Page token.
module Facebook
  class Oauth
    AUTHORIZE_URL    = "https://www.facebook.com/v21.0/dialog/oauth"
    TOKEN_URL        = "https://graph.facebook.com/v21.0/oauth/access_token"
    ME_ACCOUNTS_URL  = "https://graph.facebook.com/v21.0/me/accounts"
    DEFAULT_SCOPES   = %w[pages_show_list pages_manage_posts pages_read_engagement public_profile].freeze

    UserTokenResult = Struct.new(:ok?, :access_token, :expires_in, :error, keyword_init: true)
    PagesResult     = Struct.new(:ok?, :pages, :error, keyword_init: true)
    Page            = Struct.new(:id, :name, :access_token, keyword_init: true)

    class << self
      attr_accessor :http_stub

      def configured?
        client_id.present? && client_secret.present?
      end

      def client_id
        Rails.application.credentials.dig(:facebook, :client_id) || ENV["FACEBOOK_CLIENT_ID"]
      end

      def client_secret
        Rails.application.credentials.dig(:facebook, :client_secret) || ENV["FACEBOOK_CLIENT_SECRET"]
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
        status, body = get_json(TOKEN_URL, params: {
          client_id:     client_id,
          client_secret: client_secret,
          redirect_uri:  redirect_uri,
          code:          code
        })
        if status == "200" && body["access_token"].present?
          UserTokenResult.new(ok?: true, access_token: body["access_token"], expires_in: body["expires_in"])
        else
          UserTokenResult.new(ok?: false, error: format_error(status, body))
        end
      end

      def exchange_for_long_lived_user(short_token:)
        status, body = get_json(TOKEN_URL, params: {
          grant_type:        "fb_exchange_token",
          client_id:         client_id,
          client_secret:     client_secret,
          fb_exchange_token: short_token
        })
        if status == "200" && body["access_token"].present?
          UserTokenResult.new(ok?: true, access_token: body["access_token"], expires_in: body["expires_in"])
        else
          UserTokenResult.new(ok?: false, error: format_error(status, body))
        end
      end

      def pages(user_token:)
        status, body = get_json(ME_ACCOUNTS_URL, params: {
          access_token: user_token,
          fields:       "id,name,access_token"
        })
        if status == "200" && body["data"].is_a?(Array)
          rows = body["data"].map { |p| Page.new(id: p["id"], name: p["name"], access_token: p["access_token"]) }
          PagesResult.new(ok?: true, pages: rows)
        else
          PagesResult.new(ok?: false, pages: [], error: format_error(status, body))
        end
      rescue => e
        PagesResult.new(ok?: false, pages: [], error: "#{e.class}: #{e.message}")
      end

      private

      def get_json(url, params: {})
        return http_stub.call(:get, url, params, nil) if http_stub
        uri = URI(url)
        uri.query = URI.encode_www_form(params) if params.any?
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(Net::HTTP::Get.new(uri)) }
        body = JSON.parse(res.body.to_s) rescue {}
        [res.code, body]
      end

      def format_error(status, body)
        body ||= {}
        msg = body.dig("error", "message") || body["error_description"] || body["error"] || body["message"]
        "HTTP #{status}#{msg ? ": #{msg}" : ""}"
      end
    end
  end
end
