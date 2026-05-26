class SignInsController < ApplicationController
  include InvitationAutoAccept
  allow_unauthenticated_access
  before_action :redirect_if_authenticated, only: %i[new create code]

  # Requesting a code: cap per-IP to blunt email-bombing + user-row probing.
  rate_limit to: 6, within: 15.minutes, only: :create,
    with: -> { redirect_to sign_in_path, alert: "Too many requests — try again in a few minutes." }
  # Verifying: cap per-IP on top of the per-code MAX_ATTEMPTS.
  rate_limit to: 20, within: 15.minutes, only: :verify,
    with: -> { redirect_to sign_in_path, alert: "Too many attempts — request a new code." }

  # GET /sign_in — "Enter your email". Doubles as sign-up: unknown emails
  # become accounts on first successful verify.
  def new
  end

  # POST /sign_in — email a 6-digit code (+ a magic-link button). Enumeration-
  # safe: always advances to the code screen, whether or not the email has an
  # account, and we don't create the user until the code is verified.
  def create
    email = normalize_email(params[:email_address])
    unless email.match?(URI::MailTo::EMAIL_REGEXP)
      flash.now[:alert] = "Enter a valid email address."
      return render :new, status: :unprocessable_entity
    end

    code, plaintext = LoginCode.issue!(email_address: email, ip_address: request.remote_ip)
    SignInMailer.code(
      email:      email,
      code:       plaintext,
      link_token: code.generate_token_for(:link)
    ).deliver_later

    session[:pending_sign_in_email] = email
    redirect_to sign_in_code_path
  end

  # GET /sign_in/code — "Enter the code we emailed you".
  def code
    @email = session[:pending_sign_in_email]
    redirect_to sign_in_path and return if @email.blank?
  end

  # POST /sign_in/verify — check the typed code.
  def verify
    @email = normalize_email(params[:email_address].presence || session[:pending_sign_in_email])
    record = LoginCode.active.where(email_address: @email).order(:created_at).last

    if record&.verify(params[:code])
      record.consume!
      complete_sign_in(@email)
    else
      flash.now[:alert] = "That code is incorrect or has expired."
      render :code, status: :unprocessable_entity
    end
  end

  # GET /sign_in/link?token=… — the email's "Sign in" button (web). The token
  # is multi-use within its 10-min window (so email-scanner prefetches can't
  # burn it before the human clicks); it can't be consumed here for the same
  # reason. The typed code is the single-use path.
  def link
    record = LoginCode.find_by_token_for(:link, params[:token])
    if record && !record.expired?
      complete_sign_in(record.email_address)
    else
      redirect_to sign_in_path, alert: "That sign-in link is invalid or has expired. Enter your email for a new one."
    end
  end

  private

  def complete_sign_in(email)
    user = User.find_or_create_for_email(email)
    session.delete(:pending_sign_in_email)
    start_new_session_for(user)
    accepted = auto_accept_pending_invitations(user)
    if accepted.any?
      redirect_to workspace_path(accepted.first.workspace.slug),
        notice: "Welcome! You've joined #{accepted.map { |i| i.workspace.name }.uniq.to_sentence}."
    else
      redirect_to after_authentication_url, notice: "You're signed in."
    end
  end

  def normalize_email(value)
    value.to_s.strip.downcase
  end

  def redirect_if_authenticated
    redirect_to after_authentication_url if authenticated?
  end
end
