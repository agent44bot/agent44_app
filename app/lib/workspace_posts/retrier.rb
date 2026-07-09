module WorkspacePosts
  class Retrier
    Result = Struct.new(:ok?, :error, keyword_init: true)

    def initialize(post)
      @post = post
      @account = post.social_account
    end

    def call
      return failure("Only failed posts can be retried") unless @post.failed?
      return failure("No social account is attached to this post") unless @account
      return failure("Account is not active") unless @account.status == "active"

      result = call_client

      if result&.ok?
        @post.update!(
          status: "posted",
          error: nil,
          remote_id: remote_id_for(result),
          remote_url: remote_url_for(result),
          posted_at: Time.current
        )
        Result.new(ok?: true)
      else
        failure(result&.error || "unsupported platform")
      end
    end

    private

    def call_client
      case @post.platform
      when "x"        then post_to_x
      when "bluesky"  then post_to_bluesky
      when "threads"  then Threads::UserClient.new(@account).post_text(@post.body)
      when "facebook" then Facebook::UserClient.new(@account).post_text(@post.body)
      end
    end

    def post_to_x
      client = X::UserClient.new(@account)

      if @post.image.attached?
        upload = client.upload_media(@post.image.download, @post.image.content_type)
        return X::UserClient::Result.new(ok?: false, error: "image upload: #{upload.error}") unless upload.ok?

        return client.post_tweet(@post.body, media_ids: [ upload.media_id ])
      end

      if @post.image_url.present? && (fetched = SocialImage.fetch(@post.image_url))
        bytes, mime = fetched
        upload = client.upload_media(bytes, mime)
        return client.post_tweet(@post.body, media_ids: [ upload.media_id ]) if upload.ok?

        Rails.logger.warn("X retry url-image upload failed, posting text-only: #{upload.error}")
      end

      client.post_tweet(@post.body)
    end

    def post_to_bluesky
      client = Bluesky::UserClient.new(@account)

      if @post.image.attached?
        bytes, mime = Bluesky::ImageFit.fit(@post.image.download, @post.image.content_type)
        return client.post_text(@post.body, image_bytes: bytes, image_content_type: mime) if bytes
      end

      client.post_text(@post.body, image_url: @post.image_url)
    end

    def failure(error)
      @post.update!(status: "failed", error: error) if @post.failed? || @post.pending?
      Result.new(ok?: false, error: error)
    end

    def remote_id_for(result)
      @post.platform == "x" ? result.tweet_id : result.post_id
    end

    def remote_url_for(result)
      handle = @account.handle.to_s.delete_prefix("@")
      case @post.platform
      when "x"        then "https://x.com/#{handle}/status/#{result.tweet_id}"
      when "bluesky"  then "https://bsky.app/profile/#{handle}/post/#{result.post_id}"
      when "threads"  then result.permalink_url.presence || "https://www.threads.net/@#{handle}"
      when "facebook" then result.permalink_url
      end
    end
  end
end
