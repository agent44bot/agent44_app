require "net/http"
require "uri"

# Fetches a remote image's bytes + mime so it can be uploaded as native media
# to a social platform (e.g. X). Used for posts that carry an image_url (like
# NY Kitchen event photos) rather than an uploaded ActiveStorage attachment.
# Stubbable in tests via SocialImage.fetch_stub. Returns [bytes, mime] or nil.
module SocialImage
  class << self
    attr_accessor :fetch_stub # ->(url) { [bytes, mime] | nil }

    def fetch(url)
      return fetch_stub.call(url) if fetch_stub
      uri = URI(url.to_s)
      return nil unless %w[http https].include?(uri.scheme)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                            open_timeout: 5, read_timeout: 10) do |http|
        http.get(uri.request_uri, { "User-Agent" => "Agent44LabsBot/1.0 (+https://agent44labs.com)" })
      end
      return nil unless res.is_a?(Net::HTTPSuccess)
      [ res.body, res["Content-Type"].presence || guess_mime(url) ]
    rescue => e
      Rails.logger.warn("SocialImage.fetch failed for #{url}: #{e.class}: #{e.message}")
      nil
    end

    def guess_mime(url)
      case url.to_s.downcase
      when /\.png(\?|$)/  then "image/png"
      when /\.gif(\?|$)/  then "image/gif"
      when /\.webp(\?|$)/ then "image/webp"
      else                     "image/jpeg"
      end
    end
  end
end
