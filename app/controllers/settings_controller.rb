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

  # Permanent account deletion. Required by Apple App Store guideline 5.1.1(v).
  # Email/password users must enter their password; Nostr-only users (no
  # password_digest) must type the literal phrase "DELETE" to confirm.
  def destroy
    user = Current.user
    return redirect_to(root_path) unless user

    if user.password_digest.present?
      unless user.authenticate(params[:password].to_s)
        redirect_to settings_path, alert: "That password is incorrect." and return
      end
    else
      unless params[:confirm].to_s.strip == "DELETE"
        redirect_to settings_path, alert: 'Type "DELETE" to confirm.' and return
      end
    end

    user.destroy!
    cookies.delete(:session_id)
    Current.session = nil
    redirect_to root_path, notice: "Your account has been deleted."
  end
end
