class Workspace < ApplicationRecord
  ROLES = %w[owner admin editor viewer].freeze

  belongs_to :owner, class_name: "User"

  has_many :memberships,       class_name: "WorkspaceMembership", dependent: :destroy
  has_many :users,             through: :memberships
  has_many :invitations,       class_name: "WorkspaceInvitation", dependent: :destroy
  has_many :social_accounts,   dependent: :destroy
  has_many :workspace_posts,   dependent: :destroy
  has_many :workspace_drafts,  dependent: :destroy
  has_many :workspace_agents,  dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 }
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/ },
                   length: { maximum: 60 }
  validates :timezone, presence: true

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

  # Site admins always see pricing. Workspace members see it when the
  # workspace-level toggle is on. Non-members never see it.
  def pricing_visible_for?(user)
    return false unless user
    return true if user.admin?
    pricing_visible_to_members? && member?(user)
  end

  private

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
