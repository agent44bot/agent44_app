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
  has_many :connect_chat_messages, dependent: :nullify # keep the workspace's Q&A log if the asker is deleted
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

  # Profile photo. Uploaded as the original blob but rendered everywhere through
  # the resized #avatar_display variant (libvips is in the deploy image), so a
  # multi-MB upload never gets sent full size into a small avatar circle.
  # has_one_attached auto-purges on destroy, so the Apple delete-account flow
  # stays intact.
  has_one_attached :avatar

  AVATAR_TYPES = %w[image/png image/jpeg image/webp].freeze
  AVATAR_MAX_BYTES = 5.megabytes

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :password, length: { minimum: 8, maximum: 72 }, if: -> { password.present? }
  validates :password, confirmation: true, if: -> { password.present? }
  validates :pubkey_hex, uniqueness: true, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
  validates :npub, uniqueness: true, allow_nil: true
  validate :has_auth_method
  validate :acceptable_avatar

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

  # Per-workspace push opt-out. The platform toggles (ios/android_push_enabled)
  # are the master device switches; this is a finer gate so a user in several
  # workspaces can mute one (e.g. NY Kitchen) without silencing the others.
  # A push tagged with no workspace, or to a user who isn't a member of it
  # (e.g. a site admin on a NYK alert), has no per-workspace pref to consult and
  # is allowed through.
  def push_enabled_for_workspace?(workspace)
    return true if workspace.nil?
    membership = workspace_memberships.find_by(workspace_id: workspace.id)
    membership.nil? || membership.push_enabled?
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

  # One or two uppercase letters for the initials fallback shown when no avatar
  # is uploaded. Two letters when there's a multi-word display name, else one.
  def avatar_initials
    src = display_name.presence || email_address.presence || "?"
    parts = src.split(/\s+/)
    letters = parts.size >= 2 ? "#{parts[0][0]}#{parts[1][0]}" : src[0, 1]
    letters.to_s.upcase
  end

  # Deterministic color for the initials fallback. Literal Tailwind classes so
  # the scanner picks them up (same approach as Agent's avatar palette).
  AVATAR_PALETTE = [
    "bg-orange-600 text-white",
    "bg-emerald-600 text-white",
    "bg-sky-600 text-white",
    "bg-violet-600 text-white",
    "bg-rose-600 text-white",
    "bg-amber-600 text-white",
    "bg-teal-600 text-white",
    "bg-blue-600 text-white"
  ].freeze

  def avatar_color_classes
    AVATAR_PALETTE[id.to_i % AVATAR_PALETTE.size]
  end

  # A small, square, cached thumbnail for display. Every avatar render site goes
  # through this rather than the raw blob, which can be several MB straight off
  # an iPhone. 256px covers the largest use (a 56px circle at 3x DPR) with room
  # to spare. Falls back to the original if the file isn't variant-processable.
  def avatar_display
    return unless avatar.attached?
    return avatar unless avatar.variable?
    avatar.variant(resize_to_fill: [ 256, 256 ])
  end

  private

  def acceptable_avatar
    return unless avatar.attached?
    unless avatar.blob.content_type.in?(AVATAR_TYPES)
      errors.add(:avatar, "must be a PNG, JPEG, or WebP image")
    end
    if avatar.blob.byte_size > AVATAR_MAX_BYTES
      errors.add(:avatar, "must be 5 MB or smaller")
    end
  end

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
