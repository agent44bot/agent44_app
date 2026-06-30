# Fits a post body to a platform's character limit so a single draft can go
# out to every connected platform without one of them hard-failing on length.
#
# Strategy, in order, until it fits:
#   1. If it already fits, leave it untouched.
#   2. Drop trailing hashtags one at a time (the cheapest copy to lose).
#   3. Hard-truncate the body, preserving a trailing link, with an ellipsis.
#
# url_weight handles X's t.co rule: every link counts as 23 chars regardless of
# its real length, so a long reservation URL shouldn't blow the budget on X.
# Pass nil for platforms that count links by their literal length.
module WorkspacePosts
  class Fitter
    URL_RE   = %r{https?://\S+}
    ELLIPSIS = "…".freeze

    def self.fit(text, limit:, url_weight: nil)
      text = text.to_s
      return text if limit.nil? || weighted_length(text, url_weight) <= limit

      reduced = drop_trailing_hashtags(text, limit, url_weight)
      return reduced if weighted_length(reduced, url_weight) <= limit

      truncate_keeping_url(reduced, limit, url_weight)
    end

    # Length as the platform counts it: each link as url_weight chars when given
    # (X t.co = 23), otherwise its literal length.
    def self.weighted_length(text, url_weight)
      return text.length if url_weight.nil?
      text.gsub(URL_RE) { "x" * url_weight }.length
    end

    def self.drop_trailing_hashtags(text, limit, url_weight)
      result = text.dup
      while weighted_length(result, url_weight) > limit
        m = result.match(/\s*#[[:word:]]+\s*\z/)
        break unless m
        result = result[0...m.begin(0)].rstrip
      end
      result
    end
    private_class_method :drop_trailing_hashtags

    def self.truncate_keeping_url(text, limit, url_weight)
      url = text.scan(URL_RE).last
      if url
        body     = text[0...text.rindex(url)].rstrip
        url_cost = url_weight || url.length
        budget   = limit - url_cost - ELLIPSIS.length - 1 # 1 for the newline
        return text if budget <= 0
        "#{body[0, budget].rstrip}#{ELLIPSIS}\n#{url}"
      else
        keep = [ limit - ELLIPSIS.length, 0 ].max
        "#{text[0, keep].rstrip}#{ELLIPSIS}"
      end
    end
    private_class_method :truncate_keeping_url
  end
end
