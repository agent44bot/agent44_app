class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 1.hour, only: :create, with: -> { redirect_to new_registration_path, alert: "Too many sign-up attempts. Try again later." }

  def new
  end

  def create
    @user = User.new(registration_params)
    if @user.save
      UserMailer.email_verification(@user).deliver_later
      start_new_session_for @user
      redirect_to root_path, notice: "Welcome! Check your email to verify your account."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:display_name, :email_address, :password, :password_confirmation)
  end
end
