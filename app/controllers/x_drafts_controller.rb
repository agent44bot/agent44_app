# Approval flow for the daily X autopost. Token-gated so the approval link
# can be tapped from a Telegram/iOS notification without a session — the
# token itself is the credential. We only show the approval page to admins;
# the token + admin check together make this safe for the trial phase.
class XDraftsController < ApplicationController
  allow_unauthenticated_access only: :show
  before_action :require_admin, except: :show
  before_action :load_log

  def show
    redirect_to "/session/new" unless authenticated? && Current.session.user.admin?
  end

  def post_now
    if @log.x_post_id.present?
      redirect_to nyk_x_draft_path(token: @log.x_approval_token), notice: "Already posted (id #{@log.x_post_id})."
      return
    end

    result = XClient.post_tweet(@log.x_draft_text)
    if result.ok?
      @log.update!(
        x_post_id:    result.tweet_id,
        x_posted_at:  Time.current,
        posted_at:    @log.posted_at || Time.current
      )
      redirect_to "https://x.com/agent44bot/status/#{result.tweet_id}", allow_other_host: true
    else
      redirect_to nyk_x_draft_path(token: @log.x_approval_token), alert: "Post failed: #{result.error}"
    end
  end

  def skip
    @log.update!(x_skipped_at: Time.current)
    redirect_to "/nykitchen", notice: "Skipped — no tweet sent."
  end

  private

  def load_log
    @log = SocialPostLog.find_by!(x_approval_token: params[:token])
  end

  def require_admin
    return if authenticated? && Current.session.user.admin?
    redirect_to "/session/new", alert: "Admin sign-in required."
  end
end
