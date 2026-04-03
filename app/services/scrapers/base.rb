require "net/http"
require "json"
require "uri"

module Scrapers
  class Base
    DEFAULT_SEARCH_TERMS = %w[sdet test\ automation qa\ automation quality\ engineer test\ engineer software\ test qa\ engineer].freeze

    attr_reader :source

    def initialize(source)
      @source = source
    end

    def call
      raise NotImplementedError, "Subclasses must implement #call"
    end

    private

    def search_terms
      terms = source.search_terms
      terms.present? ? terms : DEFAULT_SEARCH_TERMS
    end

    def config
      source.config || {}
    end

    def fetch_json(url, headers: {})
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 15
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Agent44-JobScraper/1.0"
      headers.each { |k, v| request[k] = v }

      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue StandardError => e
      Rails.logger.warn("[Scraper:#{source.slug}] fetch_json failed for #{url}: #{e.message}")
      nil
    end

    def post_json(url, body:, headers: {})
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 15
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri)
      request["User-Agent"] = "Agent44-JobScraper/1.0"
      request["Content-Type"] = "application/json"
      headers.each { |k, v| request[k] = v }
      request.body = body.to_json

      response = http.request(request)
      return nil unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue StandardError => e
      Rails.logger.warn("[Scraper:#{source.slug}] post_json failed for #{url}: #{e.message}")
      nil
    end

    def relevant?(title, tags = [])
      combined = "#{title} #{flatten_tags(tags).join(' ')}".downcase
      search_terms.any? { |term| combined.include?(term.downcase) }
    end

    def categorize(title, tags = [])
      combined = "#{title} #{flatten_tags(tags).join(' ')}".downcase
      if combined.match?(/\b(contract|freelance|contractor)\b/i)
        "contract"
      elsif combined.match?(/\b(part.?time)\b/i)
        "part_time"
      else
        "full_time"
      end
    end

    def ai_augmented?(title, tags = [])
      combined = "#{title} #{flatten_tags(tags).join(' ')}".downcase
      combined.match?(/\b(ai|machine learning|ml |llm|artificial intelligence)\b/i)
    end

    def flatten_tags(tags)
      (tags || []).flat_map { |t| t.is_a?(Array) ? t.map(&:to_s) : t.to_s }
    end

    def format_salary(min_val, max_val, currency = "$")
      return "" unless min_val.present? && max_val.present?
      "#{currency}#{min_val.to_i.to_fs(:delimited)} - #{currency}#{max_val.to_i.to_fs(:delimited)}"
    end
  end
end
