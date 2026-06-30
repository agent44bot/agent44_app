require "vips" # downscaling the attached image to Bluesky's 1MB blob limit

# Dispatches a post body to the workspace's connected accounts on each
# requested platform. Creates one WorkspacePost row per platform and
# returns a Result aggregating per-platform success/failure lines.
#
# Used by:
#   WorkspacePostsController#create   — direct "Post now" path
#   WorkspaceDrafts::Publisher        — scheduled / draft-published path
module WorkspacePosts
  class Dispatcher
    Result = Struct.new(:successes, :failures, :rows, keyword_init: true) do
      def all_ok?  = failures.empty? && successes.any?
      def all_bad? = successes.empty? && failures.any?
      def partial? = successes.any? && failures.any?
    end

    # image: an ActiveStorage attachment (e.g. draft.image) uploaded as native
    # media on X. image_url stays the URL-based path Bluesky/Facebook use.
    def initialize(workspace, author:, body:, platforms:, image: nil, image_url: nil, source_url: nil)
      @workspace  = workspace
      @author     = author
      @body       = body.to_s.strip
      @platforms  = (Array(platforms).map(&:to_s) & SocialAccount::PLATFORMS)
      @image      = image if image.respond_to?(:attached?) && image.attached?
      @image_url  = image_url.presence
      @source_url = source_url.presence
    end

    def dispatch
      successes = []
      failures  = []
      rows      = []

      @platforms.each do |platform|
        account = @workspace.social_accounts.active.for_platform(platform).first
        unless account
          failures << "#{platform.titleize}: no active account connected"
          next
        end

        body = fit_for(platform)

        post = @workspace.workspace_posts.create!(
          author:         @author,
          social_account: account,
          platform:       platform,
          body:           body,
          image_url:      @image_url,
          source_url:     @source_url,
          status:         "pending"
        )
        post.image.attach(@image.blob) if @image
        rows << post

        result = call_client(platform, account, body)

        if result&.ok?
          url = remote_url_for(platform, account, result)
          post.update!(status: "posted", remote_id: remote_id_for(platform, result), remote_url: url, posted_at: Time.current)
          successes << "#{platform.titleize}: #{url}"
        else
          err = result&.error || "unsupported platform"
          post.update!(status: "failed", error: err)
          failures << "#{platform.titleize}: #{err}"
        end
      end

      Result.new(successes: successes, failures: failures, rows: rows)
    end

    private

    def call_client(platform, account, body)
      case platform
      when "x"        then post_to_x(account, body)
      when "bluesky"  then post_to_bluesky(account, body)
      when "threads"  then Threads::UserClient.new(account).post_text(body)
      when "facebook" then Facebook::UserClient.new(account).post_text(body)
      end
    end

    # Fit the body to the platform's character limit so one draft can go out
    # everywhere without a single platform hard-failing on length. X counts a
    # link as 23 chars (t.co), so links don't eat its budget.
    PLATFORM_LIMITS = {
      "x"        => X::UserClient::MAX_TWEET_LENGTH,
      "bluesky"  => Bluesky::UserClient::MAX_LENGTH,
      "threads"  => Threads::UserClient::MAX_LENGTH,
      "facebook" => Facebook::UserClient::MAX_LENGTH
    }.freeze

    def fit_for(platform)
      Fitter.fit(
        @body,
        limit:      PLATFORM_LIMITS[platform],
        url_weight: platform == "x" ? X::UserClient::TCO_URL_LENGTH : nil
      )
    end

    # X needs native media: upload the attached image first to get a media_id,
    # then attach it to the tweet. No image -> plain text tweet.
    def post_to_x(account, body)
      client = X::UserClient.new(account)
      return client.post_tweet(body) unless @image

      upload = client.upload_media(@image.download, @image.content_type)
      return X::UserClient::Result.new(ok?: false, error: "image upload: #{upload.error}") unless upload.ok?

      client.post_tweet(body, media_ids: [ upload.media_id ])
    end

    # Bluesky takes a native blob. Prefer the attached image (downscaled to fit
    # Bluesky's 1MB blob limit); fall back to the URL-based image for posts that
    # only carry an image_url. No image -> plain text.
    def post_to_bluesky(account, body)
      client = Bluesky::UserClient.new(account)
      if @image
        bytes, mime = bluesky_image_bytes
        return client.post_text(body, image_bytes: bytes, image_content_type: mime) if bytes
      end
      client.post_text(body, image_url: @image_url)
    end

    # Returns [bytes, mime] for the attached image, downscaled under Bluesky's
    # 1MB limit. Small JPEGs pass through as-is; anything bigger (or non-JPEG)
    # is re-encoded as a resized JPEG, dropping quality until it fits. Returns
    # nil if it can't get under the limit, so the post still goes out as text.
    def bluesky_image_bytes
      raw = @image.download
      return [ raw, @image.content_type ] if @image.content_type == "image/jpeg" && raw.bytesize <= Bluesky::UserClient::MAX_IMAGE_BYTES

      thumb = Vips::Image.thumbnail_buffer(raw, 1280)
      [ 80, 60, 45, 30 ].each do |q|
        jpeg = thumb.jpegsave_buffer(Q: q, strip: true)
        return [ jpeg, "image/jpeg" ] if jpeg.bytesize <= Bluesky::UserClient::MAX_IMAGE_BYTES
      end
      nil
    rescue => e
      Rails.logger.warn("bluesky_image_bytes failed: #{e.class}: #{e.message}")
      nil
    end

    def remote_id_for(platform, result)
      platform == "x" ? result.tweet_id : result.post_id
    end

    def remote_url_for(platform, account, result)
      handle = account.handle.to_s.delete_prefix("@")
      case platform
      when "x"        then "https://x.com/#{handle}/status/#{result.tweet_id}"
      when "bluesky"  then "https://bsky.app/profile/#{handle}/post/#{result.post_id}"
      when "threads"  then result.permalink_url.presence || "https://www.threads.net/@#{handle}"
      when "facebook" then result.permalink_url
      end
    end
  end
end
