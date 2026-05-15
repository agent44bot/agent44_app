class WorkspaceMembership < ApplicationRecord
  ROLES = %w[owner admin editor viewer].freeze

  belongs_to :workspace
  belongs_to :user

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :workspace_id }

  scope :owners,  -> { where(role: "owner") }
  scope :admins,  -> { where(role: %w[owner admin]) }
  scope :writers, -> { where(role: %w[owner admin editor]) }

  def owner?  = role == "owner"
  def admin?  = %w[owner admin].include?(role)
  def writer? = %w[owner admin editor].include?(role)
  def viewer? = role == "viewer"
end
