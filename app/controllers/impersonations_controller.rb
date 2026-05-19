class ImpersonationsController < ApplicationController
  before_action :require_admin_actor

  def create
    target = User.find(params[:user_id])
    if target.admin?
      redirect_back fallback_location: admin_users_path, alert: "Can't impersonate another admin."
      return
    end
    Current.session.update!(impersonated_user_id: target.id)
    ImpersonationLog.create!(actor: Current.real_user, target: target, event: "start", ip_address: request.remote_ip)
    redirect_to root_path, notice: "Now viewing as #{target.display_identifier}."
  end

  def destroy
    if Current.session&.impersonating?
      target = Current.session.impersonated_user
      Current.session.update!(impersonated_user_id: nil)
      ImpersonationLog.create!(actor: Current.real_user, target: target, event: "stop", ip_address: request.remote_ip)
      redirect_to admin_users_path, notice: "Stopped impersonating #{target.display_identifier}."
    else
      redirect_to admin_users_path
    end
  end

  private

  def require_admin_actor
    return if Current.real_user&.admin?
    redirect_to root_path, alert: "Not authorized."
  end
end
