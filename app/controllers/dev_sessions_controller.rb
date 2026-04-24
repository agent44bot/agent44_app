class DevSessionsController < ApplicationController
  allow_unauthenticated_access only: [ :create ]
  # Dev-only controller. Route isn't registered outside Rails.env.development?,
  # and the action head-401s otherwise — CSRF protection adds friction without value.
  skip_before_action :verify_authenticity_token, only: :create

  def create
    head :not_found and return unless Rails.env.development?

    user = User.find(params[:user_id])
    start_new_session_for user
    redirect_to after_authentication_url, notice: "Dev login: signed in as #{user.email_address.presence || user.pubkey_hex}"
  end
end
