class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access

  def show
    user = User.find_by(email_verification_token: params[:token])

    if user.nil?
      redirect_to root_path, alert: "Invalid verification link."
    elsif user.email_verified?
      redirect_to root_path, notice: "Email already verified."
    else
      user.verify_email!
      redirect_to root_path, notice: "Email verified successfully! Welcome to Agent44."
    end
  end

  def resend
    if authenticated? && Current.user.email_address.present? && !Current.user.email_verified?
      Current.user.send_verification_email
      redirect_back fallback_location: root_path, notice: "Verification email sent."
    else
      redirect_to root_path
    end
  end
end
