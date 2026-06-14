class User < ApplicationRecord
  has_secure_password validations: false
  has_many :sessions, dependent: :destroy
  has_many :credentials, dependent: :destroy # passkeys — :destroy required for Apple delete-account
  has_many :posts, dependent: :destroy
  has_many :page_views, dependent: :nullify
  has_many :saved_jobs, dependent: :destroy
  has_many :saved_job_listings, through: :saved_jobs, source: :job
  has_many :hidden_jobs, dependent: :destroy
  has_many :hidden_job_listings, through: :hidden_jobs, source: :job
  has_many :notifications, dependent: :nullify
  has_many :device_tokens, dependent: :nullify
  has_many :ai_call_logs, dependent: :nullify
  has_many :usage_events, dependent: :nullify        # metered actions this user triggered
  has_many :inventory_movements, dependent: :nullify # who scanned stock in/out
  has_many :inventory_captures, dependent: :nullify  # who logged a product photo/price
  has_many :grocery_receipts, foreign_key: :created_by_id, dependent: :nullify # who uploaded a grocery receipt
  has_many :workspace_memberships, dependent: :destroy
  has_many :workspaces, through: :workspace_memberships
  has_many :owned_workspaces, class_name: "Workspace", foreign_key: :owner_id, dependent: :destroy
  has_many :sent_workspace_invitations, class_name: "WorkspaceInvitation", foreign_key: :invited_by_id, dependent: :destroy
  has_many :accepted_workspace_invitations, class_name: "WorkspaceInvitation", foreign_key: :accepted_by_id, dependent: :nullify
  has_many :connected_social_accounts, class_name: "SocialAccount", foreign_key: :connected_by_id, dependent: :nullify
  has_many :authored_workspace_posts, class_name: "WorkspacePost", foreign_key: :author_id, dependent: :destroy
  has_many :authored_workspace_drafts, class_name: "WorkspaceDraft", foreign_key: :author_id, dependent: :destroy

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

  # Passwordless sign-in: find or create the account for this email. The
  # email code/link the user just completed proves ownership, so the email
  # is marked verified. Unknown emails become accounts here — this is the
  # "sign up" half of the unified passwordless flow.
  def self.find_or_create_for_email(email_address)
    user = find_or_initialize_by(email_address: email_address.to_s.strip.downcase)
    user.email_verified_at ||= Time.current
    user.save!
    user
  end

  # Stable per-user WebAuthn handle (the user.id used in passkey ceremonies),
  # generated lazily on first passkey registration.
  def ensure_webauthn_id!
    return webauthn_id if webauthn_id.present?
    update!(webauthn_id: WebAuthn.generate_user_id)
    webauthn_id
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
