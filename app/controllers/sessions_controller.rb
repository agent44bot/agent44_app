class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create challenge]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def challenge
    auth_challenge = KeypairAuthChallenge.create!(
      pubkey_hex: params[:pubkey_hex].presence
    )
    render json: {
      challenge: auth_challenge.challenge,
      expires_at: auth_challenge.expires_at.iso8601
    }
  end

  def create
    if params[:signed_event].present?
      create_from_nostr_event
    elsif params[:signature].present?
      create_from_raw_signature
    else
      create_from_email
    end
  end

  def destroy
    terminate_session
    redirect_to root_path, status: :see_other
  end

  private

  def create_from_email
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def create_from_nostr_event
    signed_event = params[:signed_event].to_unsafe_h
    challenge_value = params[:challenge]
    pubkey_hex = params[:pubkey_hex]&.downcase

    auth_challenge = KeypairAuthChallenge.active.find_by(challenge: challenge_value)

    unless auth_challenge&.valid_for_use?
      return render json: { error: "Invalid or expired challenge" }, status: :unprocessable_entity
    end

    if auth_challenge.pubkey_hex.present? && auth_challenge.pubkey_hex != pubkey_hex
      return render json: { error: "Challenge pubkey mismatch" }, status: :unprocessable_entity
    end

    unless NostrEventVerifier.verify(signed_event: signed_event, expected_challenge: challenge_value)
      return render json: { error: "Invalid signature" }, status: :unprocessable_entity
    end

    auth_challenge.consume!
    user = User.find_or_create_by!(pubkey_hex: pubkey_hex)
    start_new_session_for user

    render json: { success: true, redirect_to: root_path }
  end

  def create_from_raw_signature
    pubkey_hex = params[:pubkey_hex]&.downcase
    signature_hex = params[:signature]
    challenge_value = params[:challenge]
    message_hash = params[:message_hash]

    auth_challenge = KeypairAuthChallenge.active.find_by(challenge: challenge_value)

    unless auth_challenge&.valid_for_use?
      return render json: { error: "Invalid or expired challenge" }, status: :unprocessable_entity
    end

    if auth_challenge.pubkey_hex.present? && auth_challenge.pubkey_hex != pubkey_hex
      return render json: { error: "Challenge pubkey mismatch" }, status: :unprocessable_entity
    end

    expected_hash = Digest::SHA256.hexdigest(challenge_value)
    unless expected_hash == message_hash
      return render json: { error: "Message hash mismatch" }, status: :unprocessable_entity
    end

    unless SchnorrVerifier.verify(message_hex: message_hash, pubkey_hex: pubkey_hex, signature_hex: signature_hex)
      return render json: { error: "Invalid signature" }, status: :unprocessable_entity
    end

    auth_challenge.consume!
    user = User.find_or_create_by!(pubkey_hex: pubkey_hex)
    start_new_session_for user

    render json: { success: true, redirect_to: root_path }
  end
end
