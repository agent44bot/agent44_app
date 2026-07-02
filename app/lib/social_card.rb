require "net/http"
require "uri"
require "cgi"

# Fetches Open Graph / Twitter card metadata (title, description, image) from a
# page so we can post it as a native link preview card, the whole card being
# clickable to the URL. Used for class promos so the class photo links to the
# signup page.
#
# Best-effort: returns nil on any fetch/parse failure so the caller falls back
# to a plain post (the URL in the text stays clickable). Stubbable in tests via
# SocialCard.stub so nothing hits the network.
class SocialCard
  Card = Struct.new(:url, :title, :description, :image_url, keyword_init: true)

  MAX_BYTES = 512_000  # only need the <head>; cap the read

  class << self
    attr_accessor :stub
  end

  def self.fetch(url)
    return stub.call(url) if stub
    return nil if url.blank?

    parse(get(url), url)
  rescue => e
    Rails.logger.warn("SocialCard.fetch failed for #{url}: #{e.class}: #{e.message}")
    nil
  end

  # Pure OG/Twitter parse of an HTML string. Returns a Card or nil when there's
  # no usable title. Split out from fetch so it's testable without the network.
  def self.parse(html, url)
    return nil if html.blank?

    title = meta(html, "og:title") || meta(html, "twitter:title") || title_tag(html)
    return nil if title.blank?

    Card.new(
      url:         url,
      title:       title,
      description: meta(html, "og:description") || meta(html, "twitter:description"),
      image_url:   absolute(meta(html, "og:image") || meta(html, "twitter:image"), url)
    )
  end

  # Pulls the content of the first <meta> tag whose property/name matches key,
  # tolerant of attribute order and single/double quotes.
  def self.meta(html, key)
    html.scan(/<meta\b[^>]*>/i).each do |tag|
      next unless tag =~ /\b(?:property|name)\s*=\s*["']#{Regexp.escape(key)}["']/i
      if tag =~ /\bcontent\s*=\s*["']([^"']*)["']/i
        val = CGI.unescapeHTML(::Regexp.last_match(1)).strip
        return val.presence
      end
    end
    nil
  end

  def self.title_tag(html)
    raw = html[%r{<title[^>]*>(.*?)</title>}im, 1]
    CGI.unescapeHTML(raw.to_s).strip.presence
  end

  # Resolve a relative og:image against the page URL; leave absolute ones as-is.
  def self.absolute(image, page_url)
    return nil if image.blank?
    URI.join(page_url, image).to_s
  rescue URI::Error
    image
  end

  def self.get(url, redirects: 3)
    uri = URI(url)
    return nil unless %w[http https].include?(uri.scheme)

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                          open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri, { "User-Agent" => "Agent44LabsBot/1.0 (+https://agent44labs.com)" })
    end

    case res
    when Net::HTTPSuccess
      res.body.to_s.byteslice(0, MAX_BYTES)
    when Net::HTTPRedirection
      return nil if redirects <= 0
      get(URI.join(url, res["location"]).to_s, redirects: redirects - 1)
    end
  end
end
