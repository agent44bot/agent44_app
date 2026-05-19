module Oauth
  class ThreadsController < ApplicationController
    before_action :load_workspace, only: :connect
    before_action :require_admin,  only: :connect

    def connect
      unless ::Threads::Oauth.configured?
        redirect_to social_workspace_path(@workspace.slug),
                    alert: "Threads OAuth not configured. Add threads.client_id and threads.client_secret to Rails credentials."
        return
      end

      state = SecureRandom.urlsafe_base64(32)
      session[:threads_oauth] = {
        "state"        => state,
        "workspace_id" => @workspace.id,
        "user_id"      => current_user.id,
        "issued_at"    => Time.current.to_i
      }

      url = ::Threads::Oauth.authorization_url(redirect_uri: oauth_threads_callback_url, state: state)
      redirect_to url, allow_other_host: true
    end

    def callback
      stash = session.delete(:threads_oauth) || {}

      return halt(workspaces_path, "OAuth state mismatch.")             if params[:state].blank? || params[:state] != stash["state"]
      return halt(workspaces_path, "Threads declined: #{params[:error_description] || params[:error]}") if params[:error].present?
      return halt(workspaces_path, "Missing auth code.")                if params[:code].blank?

      workspace = Workspace.find_by(id: stash["workspace_id"])
      return halt(workspaces_path, "Workspace not found.") unless workspace

      short = ::Threads::Oauth.exchange_code(code: params[:code], redirect_uri: oauth_threads_callback_url)
      return halt(social_workspace_path(workspace.slug), "Code exchange failed: #{short.error}") unless short.ok?

      long = ::Threads::Oauth.exchange_for_long_lived(short_token: short.access_token)
      return halt(social_workspace_path(workspace.slug), "Long-lived token exchange failed: #{long.error}") unless long.ok?

      me = ::Threads::Oauth.me(access_token: long.access_token)
      return halt(social_workspace_path(workspace.slug), "Couldn't fetch Threads profile: #{me.error}") unless me.ok?

      account = workspace.social_accounts.find_or_initialize_by(platform: "threads", external_id: me.id)
      account.assign_attributes(
        connected_by:     current_user,
        handle:           "@#{me.username}",
        display_name:     me.name,
        access_token:     long.access_token,
        token_expires_at: long.expires_in ? Time.current + long.expires_in.to_i.seconds : 60.days.from_now,
        scopes:           ::Threads::Oauth::DEFAULT_SCOPES.join(","),
        status:           "active",
        last_synced_at:   Time.current
      )
      account.save!

      redirect_to social_workspace_path(workspace.slug), notice: "Connected Threads account #{account.handle}."
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

    def halt(path, message)
      redirect_to path, alert: message
    end
  end
end
