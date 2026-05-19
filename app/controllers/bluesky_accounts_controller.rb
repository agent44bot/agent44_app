# Bluesky uses a static app password instead of OAuth, so the connect flow
# is a plain form. We exchange the credentials for a session immediately to
# verify they're valid, then store the resulting JWTs.
class BlueskyAccountsController < ApplicationController
  before_action :load_workspace
  before_action :require_admin

  def new
    @handle = ""
  end

  def create
    handle   = params[:handle].to_s.strip.delete_prefix("@")
    password = params[:app_password].to_s.strip

    if handle.blank? || password.blank?
      flash.now[:alert] = "Handle and app password are both required."
      @handle = handle
      return render :new, status: :unprocessable_entity
    end

    result = Bluesky::Session.create(identifier: handle, password: password)
    unless result.ok?
      flash.now[:alert] = "Bluesky rejected those credentials: #{result.error}"
      @handle = handle
      return render :new, status: :unprocessable_entity
    end

    account = @workspace.social_accounts.find_or_initialize_by(platform: "bluesky", external_id: result.did)
    account.assign_attributes(
      connected_by:     current_user,
      handle:           "@#{result.handle}",
      display_name:     result.handle,
      access_token:     result.access_jwt,
      refresh_token:    result.refresh_jwt,
      token_secret:     password, # encrypted at rest; lets us re-create a session if both JWTs expire
      token_expires_at: Bluesky::Session::DEFAULT_EXPIRES.from_now,
      status:           "active",
      last_synced_at:   Time.current
    )
    account.save!

    redirect_to social_workspace_path(@workspace.slug), notice: "Connected Bluesky account @#{result.handle}."
  end

  private

  def load_workspace
    @workspace = Workspace.find_by!(slug: params[:workspace_slug])
  end

  def require_admin
    return if @workspace.memberships.find_by(user_id: current_user.id)&.admin?
    redirect_to social_workspace_path(@workspace.slug), alert: "Only workspace admins can connect accounts."
  end

  def current_user
    Current.user
  end
end
