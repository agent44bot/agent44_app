# One turn of the per-platform "Ask the assistant" connect-help chat, persisted
# so workspace managers can review what their members (clients) asked. Stored as
# alternating user/assistant rows, scoped to the workspace + platform + asker.
class ConnectChatMessage < ApplicationRecord
  ROLES = %w[user assistant].freeze
  MAX_CONTENT = 4_000

  belongs_to :workspace
  belongs_to :user, optional: true # null once the asker deletes their account

  validates :platform, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :content, presence: true

  scope :chronological, -> { order(:created_at, :id) }
  scope :recent_first,  -> { order(created_at: :desc, id: :desc) }
end
