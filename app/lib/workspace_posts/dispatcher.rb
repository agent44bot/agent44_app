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

    def initialize(workspace, author:, body:, platforms:)
      @workspace = workspace
      @author    = author
      @body      = body.to_s.strip
      @platforms = (Array(platforms).map(&:to_s) & SocialAccount::PLATFORMS)
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

        post = @workspace.workspace_posts.create!(
          author:         @author,
          social_account: account,
          platform:       platform,
          body:           @body,
          status:         "pending"
        )
        rows << post

        result = call_client(platform, account)

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

    def call_client(platform, account)
      case platform
      when "x"       then X::UserClient.new(account).post_tweet(@body)
      when "bluesky" then Bluesky::UserClient.new(account).post_text(@body)
      when "threads" then Threads::UserClient.new(account).post_text(@body)
      end
    end

    def remote_id_for(platform, result)
      platform == "x" ? result.tweet_id : result.post_id
    end

    def remote_url_for(platform, account, result)
      handle = account.handle.to_s.delete_prefix("@")
      case platform
      when "x"       then "https://x.com/#{handle}/status/#{result.tweet_id}"
      when "bluesky" then "https://bsky.app/profile/#{handle}/post/#{result.post_id}"
      when "threads" then result.permalink_url.presence || "https://www.threads.net/@#{handle}"
      end
    end
  end
end
