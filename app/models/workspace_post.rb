class WorkspacePost < ApplicationRecord
  STATUSES = %w[pending posted failed].freeze

  belongs_to :workspace
  belongs_to :author,         class_name: "User"
  belongs_to :social_account, optional: true

  validates :platform, presence: true, inclusion: { in: SocialAccount::PLATFORMS }
  # Same generous limit as WorkspaceDraft. Per-platform caps (X 280,
  # Bluesky 300, etc.) are enforced inside the platform UserClient at
  # publish time — keeping this row storage-permissive means a long
  # Facebook-shaped draft can fan out to FB but cleanly fail on X
  # with a helpful error instead of dying at the AR validation layer.
  validates :body,     presence: true, length: { maximum: 5000 }
  validates :status,   presence: true, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :posted, -> { where(status: "posted") }
  scope :failed, -> { where(status: "failed") }

  def posted?  = status == "posted"
  def failed?  = status == "failed"
  def pending? = status == "pending"
end
