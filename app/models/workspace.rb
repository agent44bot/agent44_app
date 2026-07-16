class Workspace < ApplicationRecord
  ROLES = %w[owner admin editor viewer].freeze

  # Free-form per-workspace preferences (JSON in the `settings` text column).
  # Currently holds hidden_social_tabs; safe to grow with other UI prefs.
  serialize :settings, coder: JSON, type: Hash

  belongs_to :owner, class_name: "User"

  has_many :memberships,       class_name: "WorkspaceMembership", dependent: :destroy
  has_many :users,             through: :memberships
  has_many :invitations,       class_name: "WorkspaceInvitation", dependent: :destroy
  has_many :social_accounts,   dependent: :destroy
  has_many :workspace_posts,   dependent: :destroy
  has_many :workspace_drafts,  dependent: :destroy
  has_many :social_leads,      dependent: :destroy
  has_many :tracked_links,     dependent: :nullify # QR redirects; keep scan history if a workspace is deleted
  has_many :workspace_agents,  dependent: :destroy
  has_many :usage_events,      dependent: :destroy # metered billable actions
  has_many :ai_call_logs,      dependent: :nullify # keep usage history if a workspace is deleted
  has_many :connect_chat_messages, dependent: :destroy # connect-help Q&A transcripts

  # Brand logo for the workspace (white-label: shown on the workspace's pages
  # in place of the generic mark). Stored on the persistent volume via
  # ActiveStorage (STORAGE_ROOT=/data/storage in prod).
  has_one_attached :logo

  LOGO_TYPES = %w[image/png image/jpeg image/webp].freeze
  LOGO_MAX_BYTES = 2.megabytes

  validates :name, presence: true, length: { maximum: 100 }
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/ },
                   length: { maximum: 60 }
  validates :timezone, presence: true
  validate :acceptable_logo

  # The main site the workspace's agents watch and pull from. Optional, but if
  # set it must be a real http(s) URL so downstream agents can fetch it.
  normalizes :source_url, with: ->(u) { u.strip.presence }
  validate :source_url_is_http

  before_validation :generate_slug, on: :create
  after_create :ensure_owner_membership

  scope :active,   -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def archived?
    archived_at.present?
  end

  def role_for(user)
    return nil unless user
    memberships.find_by(user_id: user.id)&.role
  end

  def member?(user)
    role_for(user).present?
  end

  # Workspaces that receive an automated daily digest email. Only NY Kitchen
  # has one today; members opt out via WorkspaceMembership#daily_digest_enabled.
  def daily_digest?
    slug == "nykitchen"
  end

  # Emails of members who still want this workspace's daily digest.
  def daily_digest_recipients
    memberships.where(daily_digest_enabled: true)
               .includes(:user)
               .filter_map { |m| m.user&.email_address }
               .uniq
  end

  # WorkspaceAgent row for the given kind ("list", "social", "data",
  # "test"), auto-assigning a random unused 3-digit ID on first access.
  # Subsequent calls return the same row, so the badge number is stable.
  # Used for "#207" badges and optional pet names on the NYK hub +
  # agent detail pages.
  def agent_for(kind)
    workspace_agents.find_or_create_by!(kind: kind.to_s) do |a|
      taken = workspace_agents.pluck(:agent_number)
      a.agent_number = (((100..999).to_a - taken).sample) || (100..999).to_a.sample
    end
  end

  # Elevated "owner" view of this workspace's money + usage: a site admin, or
  # the workspace's own owner/admin (e.g. Lora on NY Kitchen). Editors/viewers
  # (e.g. Chris) are excluded. This is the "between admin and user" tier — it
  # rides the existing per-workspace membership roles, no new global role.
  def manager?(user)
    return false unless user
    user.admin? || %w[owner admin].include?(role_for(user))
  end

  # Site admins + the workspace owner/admin always see pricing. Other members
  # (editor/viewer) see it only when the workspace-level toggle is on.
  # Non-members never see it.
  def pricing_visible_for?(user)
    return false unless user
    return true if manager?(user)
    pricing_visible_to_members? && member?(user)
  end

  # The workspace owner (or a site admin). The tightest tier: managers see the
  # money + cost-info dialogs, but only an owner may change the rates in them.
  def owner?(user)
    return false unless user
    user.admin? || role_for(user) == "owner"
  end

  # Per-workspace cost rate for browser smoke/test runs ($/min). Falls back to
  # the app default when unset. Set by the site admin on the billing page.
  def effective_test_rate
    test_cost_per_minute || SmokeTestRun::COST_PER_MINUTE
  end

  # Per-workspace price (cents) billed per flyer print + QR scan. Falls back to
  # the app default when unset. Set by the owner from Neon's cost info dialog.
  def effective_flyer_unit_cents
    (flyer_unit_cents.presence || UsageEvent::FLYER_UNIT_CENTS).to_i
  end

  # Flat monthly platform fee for this workspace, or 0 when waived. Falls back to
  # the given default when unset. Site-admin set on the billing page.
  def effective_base_fee(default = 50.0)
    return 0.0 if base_fee_waived?
    base_fee_dollars || default
  end

  # Raw-cost markup for this workspace's usage billing (1.0 = no markup, true
  # cost). Site-admin set on the billing page. NY Kitchen keeps its ENV-based
  # multiplier; every other workspace uses this column.
  def effective_usage_multiplier
    (usage_multiplier || 1.0).to_f
  end

  # Social platform tabs an owner/admin has hidden from the Social page (array
  # of platform keys, e.g. ["instagram", "facebook"]). Hidden for everyone,
  # including managers, until re-shown via the "Edit tabs" control.
  def hidden_social_tabs
    Array((settings || {})["hidden_social_tabs"])
  end

  def hidden_social_tabs=(keys)
    self.settings = (settings || {}).merge("hidden_social_tabs" => Array(keys).map(&:to_s).uniq)
  end

  private

  def acceptable_logo
    return unless logo.attached?
    unless logo.blob.content_type.in?(LOGO_TYPES)
      errors.add(:logo, "must be a PNG, JPEG, or WebP image")
    end
    if logo.blob.byte_size > LOGO_MAX_BYTES
      errors.add(:logo, "must be 2 MB or smaller")
    end
  end

  def source_url_is_http
    return if source_url.blank?
    uri = URI.parse(source_url)
    errors.add(:source_url, "must be a valid http or https URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    errors.add(:source_url, "must be a valid http or https URL")
  end

  def generate_slug
    return if slug.present?
    base = name.to_s.parameterize.presence || "workspace"
    base = base.first(50)
    candidate = base
    n = 2
    while Workspace.exists?(slug: candidate)
      suffix = "-#{n}"
      candidate = "#{base.first(60 - suffix.length)}#{suffix}"
      n += 1
    end
    self.slug = candidate
  end

  def ensure_owner_membership
    memberships.find_or_create_by!(user_id: owner_id) do |m|
      m.role = "owner"
    end
  end
end
