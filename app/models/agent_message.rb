class AgentMessage < ApplicationRecord
  ROLES = %w[user assistant].freeze
  STATUSES = %w[pending sent delivered failed].freeze

  validates :role, inclusion: { in: ROLES }
  validates :content, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :agent, presence: true

  scope :recent, -> { order(created_at: :asc) }
  scope :pending, -> { where(role: "user", status: "pending") }

  def user?     = role == "user"
  def assistant? = role == "assistant"
  def pending?  = status == "pending"
end
