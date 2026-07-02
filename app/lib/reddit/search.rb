require "net/http"
require "uri"
require "json"

# Free, read-only Reddit search for the social-listening feature (no auth,
# public JSON endpoints, descriptive User-Agent). Best-effort: returns [] on any
# failure so a listening run never dies on Reddit being flaky. Stubbable via
# Reddit::Search.http_stub in tests (never hits the network there).
module Reddit
  module Search
    USER_AGENT         = "Agent44LabsBot/1.0 (+https://agent44labs.com)".freeze
    DEFAULT_SUBREDDITS = %w[Rochester FingerLakes].freeze

    class << self
      # ->(url) -> parsed JSON Hash (or nil). Set in tests to avoid the network.
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
      url = "https://www.reddit.com/r/#{sub}/search.json?q=#{URI.encode_www_form_component(query)}" \
            "&restrict_sr=1&sort=new&limit=#{limit.to_i}"
      body = fetch(url)
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

    def self.fetch(url)
      return http_stub.call(url) if http_stub
      uri = URI(url)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.get(uri.request_uri, { "User-Agent" => USER_AGENT })
      end
      return nil unless res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body)
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError
      nil
    end
  end
end
