class AgentMemory < ApplicationRecord
  belongs_to :agent

  validates :body, presence: true

  # Newest first, tolerating memories that never got an occurred_at.
  scope :recent, -> { order(Arel.sql("COALESCE(occurred_at, created_at) DESC")) }

  def display_title
    title.presence || filename.to_s.sub(/\.md\z/, "").tr("-", " ")
  end
end
