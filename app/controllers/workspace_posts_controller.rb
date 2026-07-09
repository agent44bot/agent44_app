class WorkspacePostsController < ApplicationController
  before_action :load_workspace
  before_action :require_writer

  def retry
    post = @workspace.workspace_posts.find(params[:id])
    result = WorkspacePosts::Retrier.new(post).call

    if result.ok?
      redirect_to social_workspace_path(@workspace.slug), notice: "Retried #{post.platform.titleize} post."
    else
      redirect_to social_workspace_path(@workspace.slug), alert: "Retry failed — #{result.error}"
    end
  end

  def destroy
    post = @workspace.workspace_posts.find(params[:id])

    if post.posted? && post.remote_id.present? && post.social_account.present?
      result =
        case post.social_account.platform
        when "x"        then X::UserClient.new(post.social_account).delete_tweet(post.remote_id)
        when "bluesky"  then Bluesky::UserClient.new(post.social_account).delete_post(post.remote_id)
        when "threads"  then Threads::UserClient.new(post.social_account).delete_post(post.remote_id)
        when "facebook" then Facebook::UserClient.new(post.social_account).delete_post(post.remote_id)
        end

      if result && !result.ok?
        return redirect_to social_workspace_path(@workspace.slug),
                           alert: "Couldn't delete from #{post.platform.titleize} (#{result.error}). Row kept so you can retry."
      end
    end

    post.destroy!
    redirect_to social_workspace_path(@workspace.slug), notice: "Post removed."
  end

  def create
    body = params[:body].to_s.strip
    if body.blank?
      return redirect_to social_workspace_path(@workspace.slug), alert: "Post body can't be empty."
    end

    requested = Array(params[:target_platforms]).map(&:to_s) & SocialAccount::PLATFORMS
    if requested.empty?
      return redirect_to social_workspace_path(@workspace.slug), alert: "Pick at least one platform to post to."
    end

    result = WorkspacePosts::Dispatcher.new(@workspace, author: current_user, body: body, platforms: requested).dispatch

    if result.all_ok?
      redirect_to social_workspace_path(@workspace.slug), notice: "Posted — #{result.successes.join(' · ')}"
    elsif result.all_bad?
      redirect_to social_workspace_path(@workspace.slug), alert: "All posts failed — #{result.failures.join(' · ')}"
    else
      redirect_to social_workspace_path(@workspace.slug),
                  alert: "Partial: posted to #{result.successes.size}, failed #{result.failures.size}. #{result.failures.join(' · ')}"
    end
  end

  private

  def load_workspace
    @workspace = Workspace.find_by!(slug: params[:workspace_slug])
  end

  def require_writer
    membership = @workspace.memberships.find_by(user_id: current_user.id)
    return if membership&.writer?
    redirect_to social_workspace_path(@workspace.slug), alert: "Only workspace writers can post."
  end

  def current_user
    Current.user
  end
end
