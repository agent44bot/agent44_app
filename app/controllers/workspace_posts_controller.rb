class WorkspacePostsController < ApplicationController
  before_action :load_workspace
  before_action :require_writer

  def destroy
    post = @workspace.workspace_posts.find(params[:id])

    if post.posted? && post.remote_id.present? && post.social_account&.platform == "x"
      result = X::UserClient.new(post.social_account).delete_tweet(post.remote_id)
      unless result.ok?
        return redirect_to workspace_path(@workspace.slug),
                           alert: "Couldn't delete from X (#{result.error}). Row kept so you can retry."
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

    account = @workspace.social_accounts.active.for_platform("x").first
    unless account
      return redirect_to workspace_path(@workspace.slug), alert: "No active X account connected."
    end

    post = @workspace.workspace_posts.create!(
      author:         current_user,
      social_account: account,
      platform:       "x",
      body:           body,
      status:         "pending"
    )

    result = X::UserClient.new(account).post_tweet(body)

    if result.ok?
      tweet_url = "https://x.com/#{account.handle.to_s.delete_prefix('@')}/status/#{result.tweet_id}"
      post.update!(status: "posted", remote_id: result.tweet_id, remote_url: tweet_url, posted_at: Time.current)
      redirect_to workspace_path(@workspace.slug), notice: "Posted to X: #{tweet_url}"
    else
      post.update!(status: "failed", error: result.error)
      redirect_to workspace_path(@workspace.slug), alert: "Post failed: #{result.error}"
    end
  end

  private

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
