class User < ApplicationRecord
  has_secure_password validations: false
  has_many :sessions, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :page_views, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :password, length: { minimum: 8, maximum: 72 }, if: -> { password.present? }
  validates :password, confirmation: true, if: -> { password.present? }
  validates :pubkey_hex, uniqueness: true, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
  validates :npub, uniqueness: true, allow_nil: true
  validate :has_auth_method

  before_validation :derive_npub_from_pubkey, if: -> { pubkey_hex.present? && npub.blank? }

  def admin?
    role == "admin"
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
