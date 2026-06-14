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

  validates :kind, presence: true, inclusion: { in: KINDS },
            uniqueness: { scope: :workspace_id }
  validates :agent_number, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 100, less_than_or_equal_to: 999 },
            uniqueness: { scope: :workspace_id }
  validates :display_name, length: { maximum: 40 }, allow_nil: true

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
end
