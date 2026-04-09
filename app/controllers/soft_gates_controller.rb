class SoftGatesController < ApplicationController
  allow_unauthenticated_access

  def show
    @next_path = sanitize_next_path(params[:next])
    @source = params[:source].presence || "unknown"

    # Stash return URL so the existing auth flow bounces back after signup
    session[:return_to_after_authenticating] = @next_path if @next_path.present?
    session[:soft_gate_source] = @source
  end

  private

  def sanitize_next_path(path)
    return nil if path.blank?
    return nil unless path.start_with?("/")
    return nil if path.start_with?("//")
    path
  end
end
