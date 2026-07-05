require "net/http"
require "uri"
require "json"

# App-only OAuth for Reddit (the "client_credentials" grant: a confidential
# web-app registered at reddit.com/prefs/apps, NO Reddit user account needed).
# We need this because Reddit blocks the public *.json endpoints from cloud /
# datacenter IPs (Fly), so unauthenticated search returns 403 in prod. An
# authenticated request to oauth.reddit.com with a bearer token is allowed.
#
# Configure with REDDIT_CLIENT_ID / REDDIT_CLIENT_SECRET (ENV or credentials).
# Best-effort: returns nil when unconfigured or on any failure, so a listening
# run degrades gracefully (Reddit just contributes no candidates).
module Reddit
  module Auth
    TOKEN_URL = "https://www.reddit.com/api/v1/access_token".freeze
    CACHE_KEY = "reddit:app_token".freeze
    # Reddit tokens live ~1h; refresh a little early.
    TTL       = 55.minutes

    class << self
      # ->(id, secret) -> token String (or nil). Set in tests to avoid network.
      attr_accessor :token_stub
    end

    # A cached app-only bearer token, or nil if Reddit isn't configured / the
    # token fetch failed.
    def self.token
      id, secret = credentials
      return nil unless id.present? && secret.present?
      Rails.cache.fetch(CACHE_KEY, expires_in: TTL) { fetch_token(id, secret) }
    end

    def self.configured?
      id, secret = credentials
      id.present? && secret.present?
    end

    def self.credentials
      [ ENV["REDDIT_CLIENT_ID"].presence || Rails.application.credentials.dig(:reddit, :client_id),
        ENV["REDDIT_CLIENT_SECRET"].presence || Rails.application.credentials.dig(:reddit, :client_secret) ]
    end

    def self.fetch_token(id, secret)
      return token_stub.call(id, secret) if token_stub
      uri = URI(TOKEN_URL)
      req = Net::HTTP::Post.new(uri)
      req.basic_auth(id, secret)
      req.set_form_data("grant_type" => "client_credentials")
      req["User-Agent"] = Reddit::Search::USER_AGENT
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |h| h.request(req) }
      unless res.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("Reddit::Auth token fetch got #{res.code}")
        return nil
      end
      JSON.parse(res.body)["access_token"].presence
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
      Rails.logger.warn("Reddit::Auth token fetch failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
