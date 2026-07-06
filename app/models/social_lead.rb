# A social-media conversation Echo surfaced for the workspace to consider
# joining: a local foodie post, a mention of the business, etc. Found by
# SocialListenJob (Bluesky + X + Reddit search), scored + drafted by
# SocialAi::LeadScout, reviewed by a human on the Echo page. Nothing is ever
# auto-replied; draft_reply is only a suggestion until a person sends it.
class SocialLead < ApplicationRecord
  belongs_to :workspace

  STATUSES  = %w[new sent dismissed].freeze
  PLATFORMS = %w[bluesky x reddit].freeze
  PLATFORM_LABELS = { "bluesky" => "Bluesky", "x" => "X", "reddit" => "Reddit" }.freeze

  validates :platform, presence: true, inclusion: { in: PLATFORMS }
  validates :external_id, presence: true
  validates :text, presence: true
  validates :status, inclusion: { in: STATUSES }
  # One row per post per workspace (the job dedups on this before scoring).
  validates :external_id, uniqueness: { scope: %i[workspace_id platform] }

  scope :new_leads, -> { where(status: "new").order(score: :desc, posted_at: :desc) }
  scope :recent,    -> { order(created_at: :desc) }

  def platform_label
    PLATFORM_LABELS[platform] || platform.to_s.capitalize
  end
end
