class SettingsController < ApplicationController
  def show
  end

  def verify_password
    user = Current.user
    if user && user.authenticate(params[:password])
      head :no_content
    else
      head :unauthorized
    end
  end
end
