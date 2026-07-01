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

  def update_name
    user = Current.user
    return redirect_to(root_path) unless user

    name = params[:display_name].to_s.strip
    if user.update(display_name: name.presence)
      redirect_to settings_path, notice: name.present? ? "Name updated." : "Name cleared."
    else
      redirect_to settings_path, alert: user.errors.full_messages.first || "Couldn't update name."
    end
  end

  # Upload or remove the user's profile photo. Multipart form; remove_avatar=1
  # purges. On an invalid file we purge the just-attached blob so we never
  # persist a bad image (attach saves immediately on a persisted record).
  def update_avatar
    user = Current.user
    return redirect_to(root_path) unless user

    if params[:remove_avatar] == "1"
      user.avatar.purge
      return redirect_to settings_path, notice: "Profile photo removed."
    end

    if params[:avatar].blank?
      return redirect_to settings_path, alert: "Choose an image to upload."
    end

    user.avatar.attach(params[:avatar])
    if user.valid?
      redirect_to settings_path, notice: "Profile photo updated."
    else
      user.avatar.purge
      redirect_to settings_path, alert: user.errors.full_messages.first || "Couldn't update photo."
    end
  end

  # Per-platform push toggles plus per-workspace push opt-outs. The form sends
  # an explicit "1"/"0" for each via check_box's hidden fallback, so a
  # missing/unchecked box reads as off.
  def update_notifications
    user = Current.user
    return redirect_to(root_path) unless user

    attrs = {
      ios_push_enabled: ActiveModel::Type::Boolean.new.cast(params[:ios_push_enabled]),
      android_push_enabled: ActiveModel::Type::Boolean.new.cast(params[:android_push_enabled])
    }
    # NOT NULL + opt-out default: only touch it when the form actually sends it,
    # so a caller that omits the field leaves the current choice intact.
    attrs[:social_push_enabled] = ActiveModel::Type::Boolean.new.cast(params[:social_push_enabled]) if params.key?(:social_push_enabled)
    user.update(attrs)
    update_workspace_push_prefs(user)
    redirect_to settings_path, notice: "Notification settings saved."
  end

  def update_email
    return if forbid_impersonation!
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
    return if forbid_impersonation!
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

  private

  # Apply the per-workspace push toggles. Scoped to the user's own memberships
  # so a forged workspace_id can't flip another member's preference.
  def update_workspace_push_prefs(user)
    prefs = params[:workspace_push]
    return unless prefs.respond_to?(:each_pair)

    bool = ActiveModel::Type::Boolean.new
    user.workspace_memberships.where(workspace_id: prefs.keys).find_each do |membership|
      membership.update(push_enabled: bool.cast(prefs[membership.workspace_id.to_s]))
    end
  end
end
