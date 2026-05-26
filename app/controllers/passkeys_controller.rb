class PasskeysController < ApplicationController
  include InvitationAutoAccept
  # Registration (create_challenge/create/destroy) requires sign-in (default).
  # Authentication runs for signed-out users on /sign_in.
  allow_unauthenticated_access only: %i[auth_challenge authenticate]

  # ---- Registration: signed-in user adds a passkey from Settings ----

  # POST /settings/passkeys/challenge → creation options for navigator.credentials.create
  def create_challenge
    user = Current.user
    options = WebAuthn::Credential.options_for_create(
      user: {
        id:           user.ensure_webauthn_id!,
        name:         user.email_address.presence || "agent44-user",
        display_name: user.display_identifier.to_s
      },
      exclude: user.credentials.pluck(:external_id),
      authenticator_selection: { resident_key: "preferred", user_verification: "preferred" }
    )
    session[:passkey_reg_challenge] = options.challenge
    render json: options
  end

  # POST /settings/passkeys → verify attestation, store the credential
  def create
    challenge = session.delete(:passkey_reg_challenge)
    return render(json: { error: "missing challenge" }, status: :unprocessable_entity) if challenge.blank?

    webauthn_credential = WebAuthn::Credential.from_create(passkey_params)
    webauthn_credential.verify(challenge)

    credential = Current.user.credentials.create!(
      external_id: webauthn_credential.id,
      public_key:  webauthn_credential.public_key,
      sign_count:  webauthn_credential.sign_count,
      nickname:    params[:nickname].presence || "Passkey · #{Time.current.strftime('%b %-d, %Y')}"
    )
    render json: { id: credential.id, nickname: credential.nickname }, status: :created
  rescue WebAuthn::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /settings/passkeys/:id
  def destroy
    Current.user.credentials.find(params[:id]).destroy
    redirect_to settings_path, notice: "Passkey removed."
  end

  # ---- Authentication: signed-out user taps "Sign in with Face ID" ----

  # POST /sign_in/passkey/challenge → request options (discoverable, usernameless)
  def auth_challenge
    options = WebAuthn::Credential.options_for_get(user_verification: "preferred")
    session[:passkey_auth_challenge] = options.challenge
    render json: options
  end

  # POST /sign_in/passkey → verify assertion, start a session
  def authenticate
    challenge = session.delete(:passkey_auth_challenge)
    return render(json: { error: "missing challenge" }, status: :unprocessable_entity) if challenge.blank?

    webauthn_credential = WebAuthn::Credential.from_get(passkey_params)
    stored = Credential.find_by(external_id: webauthn_credential.id)
    return render(json: { error: "unknown passkey" }, status: :unprocessable_entity) unless stored

    webauthn_credential.verify(challenge, public_key: stored.public_key, sign_count: stored.sign_count)
    stored.update!(sign_count: webauthn_credential.sign_count, last_used_at: Time.current)

    user = stored.user
    start_new_session_for(user)
    auto_accept_pending_invitations(user)
    render json: { redirect_to: after_authentication_url }
  rescue WebAuthn::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # The browser posts the PublicKeyCredential JSON at the top level.
  def passkey_params
    params.permit(:id, :rawId, :type, :authenticatorAttachment,
                  response: {}, clientExtensionResults: {}).to_h
  end
end
