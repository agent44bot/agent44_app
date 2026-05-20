class WorkspaceInvitation < ApplicationRecord
  DEFAULT_TTL = 14.days

  belongs_to :workspace
  belongs_to :invited_by,  class_name: "User"
  belongs_to :accepted_by, class_name: "User", optional: true

  normalizes :email, with: ->(e) { e.to_s.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role,  presence: true, inclusion: { in: WorkspaceMembership::ROLES - %w[owner] }
  validates :token, presence: true, uniqueness: true
  validate  :unique_pending_per_email

  before_validation :assign_token,      on: :create
  before_validation :assign_expires_at, on: :create

  scope :pending, -> { where(accepted_at: nil, revoked_at: nil).where("expires_at > ?", Time.current) }
  scope :expired, -> { where(accepted_at: nil, revoked_at: nil).where("expires_at <= ?", Time.current) }

  def accepted?  = accepted_at.present?
  def revoked?   = revoked_at.present?
  def expired?   = !accepted? && !revoked? && expires_at && expires_at <= Time.current
  def pending?   = !accepted? && !revoked? && !expired?

  class EmailMismatch < StandardError; end

  def accept!(user)
    raise "Invitation no longer accepting" unless pending?
    raise EmailMismatch, "Invitation was sent to #{email}" unless email_matches?(user)
    transaction do
      workspace.memberships.find_or_create_by!(user_id: user.id) { |m| m.role = role }
      update!(accepted_at: Time.current, accepted_by: user)
    end
  end

  def email_matches?(user)
    return false if user&.email_address.blank?
    user.email_address.downcase == email.downcase
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  private

  def assign_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end

  def assign_expires_at
    self.expires_at ||= DEFAULT_TTL.from_now
  end

  def unique_pending_per_email
    return if workspace_id.blank? || email.blank?
    scope = WorkspaceInvitation.where(workspace_id: workspace_id, email: email, accepted_at: nil, revoked_at: nil)
                               .where("expires_at > ?", Time.current)
    scope = scope.where.not(id: id) if persisted?
    errors.add(:email, "already has a pending invitation") if scope.exists?
  end
end
