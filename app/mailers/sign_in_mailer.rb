class SignInMailer < ApplicationMailer
  # The one email that powers passwordless sign-in: a 6-digit code (typed
  # into the app or web) plus a "Sign in" button (web magic link). Same
  # email for new and returning users.
  def code(email:, code:, link_token:)
    @code     = code
    @link_url = sign_in_link_url(token: link_token)
    mail to: email, subject: "Your Agent44 sign-in code: #{code}"
  end
end
