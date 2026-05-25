class LoginCode < ApplicationRecord
  # Short-lived, single-use email login code for passwordless sign-in.
  # The plaintext 6-digit code is shown to the user once (emailed) and only
  # its bcrypt digest is stored, so a DB leak can't be replayed. The same
  # record also backs the email's "Sign in" magic-link button via
  # generates_token_for(:link).
  has_secure_password :code, validations: false

  CODE_LENGTH  = 6
  EXPIRY       = 10.minutes
  MAX_ATTEMPTS = 5

  # The magic link references this record (not a user — the account may not
  # exist yet). Multi-use within the expiry window so corporate email-scanner
  # prefetches can't burn it before the human clicks; it dies at expires_at.
  generates_token_for :link, expires_in: EXPIRY do
    email_address
  end

  normalizes :email_address, with: ->(e) { e.to_s.strip.downcase }

  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :active, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  # Mint a fresh code for an email, invalidating any earlier unconsumed ones
  # so only the latest works. Returns [record, plaintext_code].
  def self.issue!(email_address:, ip_address: nil)
    normalized = email_address.to_s.strip.downcase
    where(email_address: normalized, consumed_at: nil).update_all(consumed_at: Time.current)
    plaintext = SecureRandom.random_number(10**CODE_LENGTH).to_s.rjust(CODE_LENGTH, "0")
    record = create!(
      email_address: normalized,
      code:          plaintext,
      expires_at:    EXPIRY.from_now,
      ip_address:    ip_address
    )
    [record, plaintext]
  end

  def expired?
    expires_at <= Time.current
  end

  def consumed?
    consumed_at.present?
  end

  def usable?
    !consumed? && !expired? && attempt_count < MAX_ATTEMPTS
  end

  def consume!
    update!(consumed_at: Time.current)
  end

  # Check a submitted code against this record. Counts the attempt first so a
  # brute-forcer burns through MAX_ATTEMPTS regardless of outcome. Returns
  # true only when usable and the digest matches.
  def verify(submitted)
    return false unless usable?
    increment!(:attempt_count)
    authenticate_code(submitted.to_s.strip) ? true : false
  end
end
