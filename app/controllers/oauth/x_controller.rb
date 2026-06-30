module Oauth
  class XController < ApplicationController
    before_action :load_workspace, only: :connect
    before_action :require_admin,  only: :connect

    def connect
      unless ::X::Oauth.configured?
        redirect_to social_workspace_path(@workspace.slug),
                    alert: "X OAuth not configured. Add x.oauth_client_id and x.oauth_client_secret to Rails credentials."
        return
      end

      verifier = ::X::Oauth.generate_verifier
      state    = SecureRandom.urlsafe_base64(32)

      session[:x_oauth] = {
        "verifier"     => verifier,
        "state"        => state,
        "workspace_id" => @workspace.id,
        "user_id"      => current_user.id,
        "issued_at"    => Time.current.to_i
      }

      url = ::X::Oauth.authorization_url(
        redirect_uri:  oauth_x_callback_url,
        state:         state,
        code_verifier: verifier
      )
      redirect_to url, allow_other_host: true
    end

    def callback
      stash = session.delete(:x_oauth) || {}

      return halt(workspaces_path, "OAuth state mismatch.")          if params[:state].blank? || params[:state] != stash["state"]
      return halt(workspaces_path, "X declined: #{params[:error]}")  if params[:error].present?
      return halt(workspaces_path, "Missing auth code.")             if params[:code].blank?

      workspace = Workspace.find_by(id: stash["workspace_id"])
      return halt(workspaces_path, "Workspace not found.") unless workspace

      token = ::X::Oauth.exchange_code(
        code:          params[:code],
        redirect_uri:  oauth_x_callback_url,
        code_verifier: stash["verifier"].to_s
      )
      return halt(social_workspace_path(workspace.slug), "Token exchange failed: #{token.error}") unless token.ok?

      # Observability: the granted scope is the usual reason /2/users/me 401s
      # (users.read missing). Log it so a failed connect is diagnosable.
      Rails.logger.info("[oauth/x] exchange ok for #{workspace.slug}: scope=#{token.scope.inspect} token_type=#{token.token_type.inspect}")

      me = ::X::Oauth.me(access_token: token.access_token)
      return halt(social_workspace_path(workspace.slug), "Couldn't fetch X profile: #{me.error}") unless me.ok?

      account = workspace.social_accounts.find_or_initialize_by(platform: "x", external_id: me.id)
      account.assign_attributes(
        connected_by:     current_user,
        handle:           "@#{me.username}",
        display_name:     me.name,
        access_token:     token.access_token,
        refresh_token:    token.refresh_token,
        token_expires_at: token.expires_in ? Time.current + token.expires_in.to_i.seconds : nil,
        scopes:           token.scope,
        status:           "active",
        last_synced_at:   Time.current
      )
      account.save!

      redirect_to social_workspace_path(workspace.slug), notice: "Connected X account #{account.handle}."
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
      Rails.logger.warn("[oauth/x] connect halted: #{message}")
      redirect_to path, alert: message
    end
  end
end
