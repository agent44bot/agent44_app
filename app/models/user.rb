class User < ApplicationRecord
  has_secure_password validations: false
  has_many :sessions, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :page_views, dependent: :nullify
  has_many :saved_jobs, dependent: :destroy
  has_many :saved_job_listings, through: :saved_jobs, source: :job
  has_many :hidden_jobs, dependent: :destroy
  has_many :hidden_job_listings, through: :hidden_jobs, source: :job
  has_many :notifications, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :password, length: { minimum: 8, maximum: 72 }, if: -> { password.present? }
  validates :password, confirmation: true, if: -> { password.present? }
  validates :pubkey_hex, uniqueness: true, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
  validates :npub, uniqueness: true, allow_nil: true
  validate :has_auth_method

  before_validation :derive_npub_from_pubkey, if: -> { pubkey_hex.present? && npub.blank? }
  before_create :generate_email_verification_token, if: -> { email_address.present? }

  def admin?
    role == "admin"
  end

  # App Store reviewers and other read-mostly demo accounts. Sees the same
  # rich kitchen view as admins (smoke run management, pricing) so the
  # marketed feature set is visible during review, but is denied access to
  # admin internals (/admin/*, /lab).
  def reviewer?
    role == "reviewer"
  end

  # Customers scoped to a single page (today: NY Kitchen). They bypass the
  # normal admin tools and are pinned to /nykitchen on sign-in and redirected
  # back if they try to visit anything else.
  def kitchen_only?
    role == "kitchen_customer"
  end

  def email_verified?
    email_verified_at.present?
  end

  def verify_email!
    update!(email_verified_at: Time.current, email_verification_token: nil)
  end

  def generate_email_verification_token
    self.email_verification_token = SecureRandom.urlsafe_base64(32)
  end

  def send_verification_email
    generate_email_verification_token
    save!
    UserMailer.email_verification(self).deliver_later
  end

  def display_identifier
    display_name.presence || email_address.presence || short_npub
  end

  def short_npub
    return nil unless npub
    "#{npub[0..8]}...#{npub[-4..]}"
  end

  private

  def derive_npub_from_pubkey
    entity = Bech32::Nostr::BareEntity.new("npub", pubkey_hex)
    self.npub = entity.encode
  rescue StandardError
    errors.add(:pubkey_hex, "could not derive npub")
  end

  def has_auth_method
    if email_address.blank? && pubkey_hex.blank?
      errors.add(:base, "Must have either an email address or a Nostr public key")
    end
  end
end
