require "net/http"
require "uri"
require "json"

# Read-only Reddit search for the social-listening feature. Prefers authed
# app-only OAuth (oauth.reddit.com + bearer token, see Reddit::Auth) because
# Reddit 403s the public *.json endpoints from cloud IPs; falls back to the
# public host when no token is configured (works from a laptop, not from Fly).
# Best-effort: returns [] on any failure so a listening run never dies on Reddit
# being flaky. Stubbable via Reddit::Search.http_stub in tests (no network).
module Reddit
  module Search
    USER_AGENT         = "Agent44LabsBot/1.0 (+https://agent44labs.com)".freeze
    DEFAULT_SUBREDDITS = %w[Rochester FingerLakes].freeze
    OAUTH_HOST         = "https://oauth.reddit.com".freeze
    PUBLIC_HOST        = "https://www.reddit.com".freeze

    class << self
      # ->(url, bearer) -> parsed JSON Hash (or nil). Set in tests (no network).
      attr_accessor :http_stub
    end

    # [{external_id:, author:, text:, url:, posted_at:}] for posts in the given
    # subreddits whose title/body matches the query.
    def self.posts(query, subreddits: DEFAULT_SUBREDDITS, limit: 15)
      return [] if query.to_s.strip.empty?
      Array(subreddits).flat_map { |sub| search_subreddit(sub, query, limit) }
    rescue => e
      Rails.logger.warn("Reddit::Search failed for #{query.inspect}: #{e.class}: #{e.message}")
      []
    end

    def self.search_subreddit(sub, query, limit)
      bearer = Reddit::Auth.token
      host   = bearer ? OAUTH_HOST : PUBLIC_HOST
      url = "#{host}/r/#{sub}/search.json?q=#{URI.encode_www_form_component(query)}" \
            "&restrict_sr=1&sort=new&limit=#{limit.to_i}&raw_json=1"
      body = fetch(url, bearer)
      return [] unless body
      Array(body.dig("data", "children")).map { |c| parse_post(c["data"]) }.compact
    end

    def self.parse_post(data)
      return nil if data.nil?
      text = [ data["title"], data["selftext"] ].reject(&:blank?).join(" - ")
      return nil if text.strip.empty?
      {
        external_id: data["name"].to_s, # e.g. "t3_abc123"
        author:      data["author"],
        text:        text.first(2000),
        url:         data["permalink"] ? "https://www.reddit.com#{data['permalink']}" : data["url"],
        posted_at:   data["created_utc"] ? Time.zone.at(data["created_utc"].to_i) : nil
      }
    end

    def self.fetch(url, bearer = nil)
      return http_stub.call(url, bearer) if http_stub
      uri = URI(url)
      headers = { "User-Agent" => USER_AGENT }
      headers["Authorization"] = "Bearer #{bearer}" if bearer
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.get(uri.request_uri, headers)
      end
      return nil unless res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body)
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError
      nil
    end
  end
end
