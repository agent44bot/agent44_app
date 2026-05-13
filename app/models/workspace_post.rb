class WorkspacePost < ApplicationRecord
  STATUSES = %w[pending posted failed].freeze

  belongs_to :workspace
  belongs_to :author,         class_name: "User"
  belongs_to :social_account, optional: true

  validates :platform, presence: true, inclusion: { in: SocialAccount::PLATFORMS }
  validates :body,     presence: true, length: { maximum: 280 }
  validates :status,   presence: true, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :posted, -> { where(status: "posted") }
  scope :failed, -> { where(status: "failed") }

  def posted?  = status == "posted"
  def failed?  = status == "failed"
  def pending? = status == "pending"
end
