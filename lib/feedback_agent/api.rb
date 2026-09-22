require "json"
require "net/http"
require "uri"
require "fileutils"

module FeedbackAgent
  # The app's /api/v1/feedbacks endpoints, with the shared API_TOKEN.
  class Api
    class Conflict < StandardError; end
    class Error < StandardError; end

    def initialize(base_url:, token:)
      @base = base_url.chomp("/")
      @token = token
    end

    def queue = request(:get, "/api/v1/feedbacks/queue").fetch("feedbacks")
    def claim(id) = request(:post, "/api/v1/feedbacks/#{id}/claim")
    def plan(id, plan:, question: nil) = request(:post, "/api/v1/feedbacks/#{id}/plan", plan: plan, question: question)
    def pr(id, **fields) = request(:post, "/api/v1/feedbacks/#{id}/pr", **fields)
    def shipped(id, sha:) = request(:post, "/api/v1/feedbacks/#{id}/shipped", sha: sha)
    def error(id, message:) = request(:post, "/api/v1/feedbacks/#{id}/error", message: message)

    # Attachment URLs are signed Active Storage links; follow the redirect to
    # the blob and write it to `path`.
    def download(url, path, limit: 5)
      raise Error, "too many redirects for #{url}" if limit.zero?
      uri = URI(url)
      res = Net::HTTP.get_response(uri)
      case res
      when Net::HTTPRedirection then download(URI.join(url, res["location"]).to_s, path, limit: limit - 1)
      when Net::HTTPSuccess
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, res.body)
      else raise Error, "download #{res.code} for #{url}"
      end
    end

    private

    def request(verb, path, **body)
      uri = URI("#{@base}#{path}")
      req = (verb == :get ? Net::HTTP::Get : Net::HTTP::Post).new(uri)
      req["Authorization"] = "Bearer #{@token}"
      req["Accept"] = "application/json"
      unless verb == :get
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body.compact)
      end
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 60) { |h| h.request(req) }
      json = res.body.to_s.empty? ? {} : JSON.parse(res.body)
      case res.code.to_i
      when 200..299 then json
      when 409 then raise Conflict, json["error"].to_s
      else raise Error, "#{verb.upcase} #{path}: #{res.code} #{json['error'] || res.body.to_s[0, 200]}"
      end
    end
  end
end
