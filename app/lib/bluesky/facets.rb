# Builds the Bluesky facets array from post text. Without this, links and
# hashtags render as plain text in bsky.app (not clickable). Bluesky uses
# BYTE offsets, not char offsets, so we slice prefixes with .bytesize to
# handle emoji / multibyte characters correctly.
#
# https://docs.bsky.app/docs/advanced-guides/post-richtext#text-encoding-and-indexing
module Bluesky
  module Facets
    # Stop at whitespace and a small set of trailing chars that almost always
    # mark the end of a URL in prose. We also strip trailing sentence-end
    # punctuation after the match (period / comma / etc.) so "visit foo.com."
    # links foo.com, not foo.com.
    URL_RE     = %r{https?://[^\s)\]"'>]+}
    URL_TRAIL  = /[.,;!?)\]'"]+\z/
    HASHTAG_RE = /(?<![\w&])(#)([A-Za-z0-9_]+)/

    def self.build(text)
      return [] if text.to_s.empty?
      [link_facets(text), tag_facets(text)].flatten
    end

    def self.link_facets(text)
      scan_with_match(text, URL_RE).map do |m|
        raw   = m[0]
        clean = raw.sub(URL_TRAIL, "")
        next nil if clean.empty?
        byte_start = text[0, m.begin(0)].bytesize
        byte_end   = byte_start + clean.bytesize
        {
          index:    { byteStart: byte_start, byteEnd: byte_end },
          features: [{ "$type" => "app.bsky.richtext.facet#link", uri: clean }]
        }
      end.compact
    end

    def self.tag_facets(text)
      scan_with_match(text, HASHTAG_RE).map do |m|
        # m[0] = "#NYKitchen", m[2] = "NYKitchen" (the tag without the #)
        byte_start = text[0, m.begin(0)].bytesize
        byte_end   = byte_start + m[0].bytesize
        {
          index:    { byteStart: byte_start, byteEnd: byte_end },
          features: [{ "$type" => "app.bsky.richtext.facet#tag", tag: m[2] }]
        }
      end
    end

    # String#scan doesn't expose MatchData inside the block in a way that
    # survives multi-platform regex evaluation cleanly, so iterate manually.
    def self.scan_with_match(text, re)
      matches = []
      pos = 0
      while (m = text.match(re, pos))
        matches << m
        pos = m.end(0)
        # Guard against zero-width matches (would infinite-loop)
        pos += 1 if m.end(0) == m.begin(0)
      end
      matches
    end

    # text.byteslice(0, char_index) returns the bytes up to a character
    # index — we use String#match positions (character offsets) and convert
    # via this. Ruby's String API expresses #match offsets in characters
    # when the regex isn't binary-tagged, which matches our text.
    def self.byteslice_helper_warning_only_; end
  end
end
