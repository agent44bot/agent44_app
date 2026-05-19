module Oauth
  class FacebookController < ApplicationController
    before_action :load_workspace, only: :connect
    before_action :require_admin,  only: :connect

    def connect
      unless ::Facebook::Oauth.configured?
        redirect_to social_workspace_path(@workspace.slug),
                    alert: "Facebook OAuth not configured. Add facebook.client_id and facebook.client_secret to Rails credentials."
        return
      end

      state = SecureRandom.urlsafe_base64(32)
      session[:facebook_oauth] = {
        "state"        => state,
        "workspace_id" => @workspace.id,
        "user_id"      => current_user.id,
        "issued_at"    => Time.current.to_i
      }

      url = ::Facebook::Oauth.authorization_url(redirect_uri: oauth_facebook_callback_url, state: state)
      redirect_to url, allow_other_host: true
    end

    def callback
      stash = session.delete(:facebook_oauth) || {}

      return halt(workspaces_path, "OAuth state mismatch.")          if params[:state].blank? || params[:state] != stash["state"]
      return halt(workspaces_path, "Facebook declined: #{params[:error_description] || params[:error]}") if params[:error].present?
      return halt(workspaces_path, "Missing auth code.")             if params[:code].blank?

      workspace = Workspace.find_by(id: stash["workspace_id"])
      return halt(workspaces_path, "Workspace not found.") unless workspace

      short = ::Facebook::Oauth.exchange_code(code: params[:code], redirect_uri: oauth_facebook_callback_url)
      return halt(social_workspace_path(workspace.slug), "Code exchange failed: #{short.error}") unless short.ok?

      long = ::Facebook::Oauth.exchange_for_long_lived_user(short_token: short.access_token)
      return halt(social_workspace_path(workspace.slug), "Long-lived token exchange failed: #{long.error}") unless long.ok?

      pages = ::Facebook::Oauth.pages(user_token: long.access_token)
      return halt(social_workspace_path(workspace.slug), "Couldn't fetch Pages: #{pages.error}") unless pages.ok?
      if pages.pages.empty?
        return halt(social_workspace_path(workspace.slug),
                    "No Facebook Pages found for that account. Create one at facebook.com/pages/create first.")
      end

      # MVP: auto-pick the first Page. If you manage multiple Pages and want a
      # picker UI, that's a follow-up — for now reconnect to switch.
      page = pages.pages.first
      account = workspace.social_accounts.find_or_initialize_by(platform: "facebook", external_id: page.id)
      account.assign_attributes(
        connected_by:     current_user,
        handle:           page.name,
        display_name:     page.name,
        access_token:     page.access_token,
        token_expires_at: nil, # Page tokens are effectively permanent
        scopes:           ::Facebook::Oauth::DEFAULT_SCOPES.join(","),
        status:           "active",
        last_synced_at:   Time.current
      )
      account.save!

      msg = pages.pages.size > 1 ? "Connected Facebook Page “#{page.name}” (you manage #{pages.pages.size} pages — reconnect to pick another)." \
                                 : "Connected Facebook Page “#{page.name}”."
      redirect_to social_workspace_path(workspace.slug), notice: msg
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
      Current.session.user
    end

    def halt(path, message)
      redirect_to path, alert: message
    end
  end
end
