class WorkspaceAgent < ApplicationRecord
  KINDS = %w[list social data test display ask analyst].freeze

  # Per-kind setting defaults. Used by `setting(key)` so callers can read
  # without checking whether a value has been persisted yet.
  DEFAULT_SETTINGS = {
    "analyst" => {
      # User IDs opted in to the Friday weekly sales recap email.
      "weekly_email_subscriber_ids" => []
    },
    "display" => {
      "visibility"       => "public",
      "share_token"      => nil,
      "slide_count"      => 5,
      "advance_seconds"  => 10,
      "refresh_minutes"  => 10,
      "show_price"       => true,
      "show_spots"       => true,
      "show_end_time"    => true,
      "show_image"       => false,
      "show_qr"          => true
    }
  }.freeze

  belongs_to :workspace

  # Optional per-bot profile photo. When none is set the roster falls back to
  # the shared stock avatar (avatars/bot.png) via workspace_agent_avatar_tag.
  # Renders go through #avatar_display so a multi-MB upload is never sent full
  # size into a small avatar circle. has_one_attached auto-purges on destroy.
  has_one_attached :avatar

  AVATAR_TYPES = %w[image/png image/jpeg image/webp].freeze
  AVATAR_MAX_BYTES = 5.megabytes

  validates :kind, presence: true, inclusion: { in: KINDS },
            uniqueness: { scope: :workspace_id }
  validates :agent_number, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 100, less_than_or_equal_to: 999 },
            uniqueness: { scope: :workspace_id }
  validates :display_name, length: { maximum: 40 }, allow_nil: true
  validate :acceptable_avatar

  # Title row label: pet name + badge, or just "<Kind> Agent · #207".
  # Caller already renders the bold/dim treatment.
  def display_label
    if display_name.present?
      "#{display_name} · ##{agent_number}"
    else
      "##{agent_number}"
    end
  end

  # Read a setting with kind-aware defaults. Returns the persisted value
  # if present, otherwise the DEFAULT_SETTINGS entry, otherwise nil.
  def setting(key)
    key = key.to_s
    return settings[key] if settings.key?(key)
    DEFAULT_SETTINGS.dig(kind, key)
  end

  # Merge partial updates into settings. Caller passes a hash; only the
  # keys provided are touched.
  def update_settings(partial)
    self.settings = settings.merge(partial.stringify_keys)
    save
  end

  # Returns the persisted share_token, generating + saving one on first
  # access. Used by the Display Agent's private mode to gate the TV URL.
  def rotate_share_token!
    update_settings(share_token: SecureRandom.urlsafe_base64(16))
    setting(:share_token)
  end

  def share_token_or_generate!
    setting(:share_token).presence || rotate_share_token!
  end

  # A small, square, cached thumbnail of the bot's profile photo. Mirrors
  # User#avatar_display: every render site goes through this rather than the raw
  # blob (which can be several MB straight off a phone). Returns nil when no
  # photo is set so callers fall back to the stock avatar.
  def avatar_display
    return unless avatar.attached?
    return avatar unless avatar.variable?
    avatar.variant(resize_to_fill: [ 256, 256 ])
  end

  private

  def acceptable_avatar
    return unless avatar.attached?
    unless avatar.blob.content_type.in?(AVATAR_TYPES)
      errors.add(:avatar, "must be a PNG, JPEG, or WebP image")
    end
    if avatar.blob.byte_size > AVATAR_MAX_BYTES
      errors.add(:avatar, "must be under 5MB")
    end
  end
end
