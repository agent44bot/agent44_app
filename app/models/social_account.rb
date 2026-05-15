class SocialAccount < ApplicationRecord
  PLATFORMS = %w[x bluesky nostr threads instagram facebook linkedin].freeze
  STATUSES  = %w[active needs_reauth revoked].freeze

  encrypts :access_token, :refresh_token, :token_secret

  belongs_to :workspace
  belongs_to :connected_by, class_name: "User", optional: true
  has_many   :workspace_posts, dependent: :nullify

  validates :platform, presence: true, inclusion: { in: PLATFORMS }
  validates :status,   presence: true, inclusion: { in: STATUSES }
  validates :external_id, uniqueness: { scope: [:workspace_id, :platform] }, allow_nil: true

  scope :active,        -> { where(status: "active") }
  scope :needs_reauth,  -> { where(status: "needs_reauth") }
  scope :for_platform,  ->(p) { where(platform: p.to_s) }

  def label
    display_name.presence || handle.presence || "#{platform} account"
  end

  def expired?
    token_expires_at.present? && token_expires_at <= Time.current
  end

  def mark_needs_reauth!
    update!(status: "needs_reauth")
  end
end
