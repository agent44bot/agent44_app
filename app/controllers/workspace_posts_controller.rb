class WorkspacePostsController < ApplicationController
  before_action :load_workspace
  before_action :require_writer

  def destroy
    post = @workspace.workspace_posts.find(params[:id])

    if post.posted? && post.remote_id.present? && post.social_account.present?
      result =
        case post.social_account.platform
        when "x"       then X::UserClient.new(post.social_account).delete_tweet(post.remote_id)
        when "bluesky" then Bluesky::UserClient.new(post.social_account).delete_post(post.remote_id)
        when "threads" then Threads::UserClient.new(post.social_account).delete_post(post.remote_id)
        end

      if result && !result.ok?
        return redirect_to workspace_path(@workspace.slug),
                           alert: "Couldn't delete from #{post.platform.titleize} (#{result.error}). Row kept so you can retry."
      end
    end

    post.destroy!
    redirect_to workspace_path(@workspace.slug), notice: "Post removed."
  end

  def create
    body = params[:body].to_s.strip
    if body.blank?
      return redirect_to workspace_path(@workspace.slug), alert: "Post body can't be empty."
    end

    requested = Array(params[:target_platforms]).map(&:to_s) & SocialAccount::PLATFORMS
    if requested.empty?
      return redirect_to workspace_path(@workspace.slug), alert: "Pick at least one platform to post to."
    end

    successes = []
    failures  = []

    requested.each do |platform|
      account = @workspace.social_accounts.active.for_platform(platform).first
      unless account
        failures << "#{platform.titleize}: no active account connected"
        next
      end

      post = @workspace.workspace_posts.create!(
        author:         current_user,
        social_account: account,
        platform:       platform,
        body:           body,
        status:         "pending"
      )

      result =
        case platform
        when "x"       then X::UserClient.new(account).post_tweet(body)
        when "bluesky" then Bluesky::UserClient.new(account).post_text(body)
        when "threads" then Threads::UserClient.new(account).post_text(body)
        end

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

    if failures.empty?
      redirect_to workspace_path(@workspace.slug), notice: "Posted — #{successes.join(' · ')}"
    elsif successes.empty?
      redirect_to workspace_path(@workspace.slug), alert: "All posts failed — #{failures.join(' · ')}"
    else
      redirect_to workspace_path(@workspace.slug),
                  alert: "Partial: posted to #{successes.size}, failed #{failures.size}. #{failures.join(' · ')}"
    end
  end

  private

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

  def load_workspace
    @workspace = Workspace.find_by!(slug: params[:workspace_slug])
  end

  def require_writer
    membership = @workspace.memberships.find_by(user_id: current_user.id)
    return if membership&.writer?
    redirect_to workspace_path(@workspace.slug), alert: "Only workspace writers can post."
  end

  def current_user
    Current.session.user
  end
end
