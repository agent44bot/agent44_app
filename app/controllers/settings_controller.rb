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

  def update_email
    user = Current.user
    new_email = params[:email_address].to_s.strip

    return head :unauthorized unless user&.authenticate(params[:password])
    return render json: { error: "That's already your email." }, status: :unprocessable_entity if new_email.casecmp(user.email_address.to_s) == 0

    user.email_address = new_email
    user.email_verified_at = nil
    user.generate_email_verification_token

    if user.save
      UserMailer.email_verification(user).deliver_later
      render json: { email_address: user.email_address }, status: :ok
    else
      render json: { error: user.errors.full_messages.first || "Couldn't update email." }, status: :unprocessable_entity
    end
  end
end
