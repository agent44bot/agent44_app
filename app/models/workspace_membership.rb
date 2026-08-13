class WorkspaceMembership < ApplicationRecord
  ROLES = %w[owner admin editor viewer].freeze

  belongs_to :workspace
  belongs_to :user

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :workspace_id }

  scope :owners,  -> { where(role: "owner") }
  scope :admins,  -> { where(role: %w[owner admin]) }
  scope :writers, -> { where(role: %w[owner admin editor]) }

  # Signed, login-free token behind the "turn these off" link in Echo's daily
  # email. Carries only this membership's id, so a token can never switch off
  # someone else's email; no expiry, because an old email should still work.
  UNSUBSCRIBE_PURPOSE = "echo_email_unsubscribe".freeze

  def echo_unsubscribe_token
    Rails.application.message_verifier(UNSUBSCRIBE_PURPOSE).generate(id)
  end

  def self.find_by_echo_unsubscribe_token(token)
    id = Rails.application.message_verifier(UNSUBSCRIBE_PURPOSE).verified(token.to_s)
    id && find_by(id: id)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def owner?  = role == "owner"
  def admin?  = %w[owner admin].include?(role)
  def writer? = %w[owner admin editor].include?(role)
  def viewer? = role == "viewer"
end
