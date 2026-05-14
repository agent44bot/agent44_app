class WorkspaceDraft < ApplicationRecord
  STATUSES = %w[draft scheduled published partial failed].freeze

  belongs_to :workspace
  belongs_to :author, class_name: "User"

  serialize :target_platforms, coder: JSON, type: Array
  serialize :results,          coder: JSON, type: Array

  validates :body,   presence: true, length: { maximum: 500 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validate  :target_platforms_known
  validate  :scheduled_for_in_future, if: -> { status == "scheduled" }

  scope :recent,    -> { order(created_at: :desc) }
  scope :unscheduled, -> { where(status: "draft") }
  scope :scheduled,   -> { where(status: "scheduled").order(scheduled_for: :asc) }
  scope :due_now,     -> { where(status: "scheduled").where("scheduled_for <= ?", Time.current) }
  scope :history,     -> { where(status: %w[published partial failed]).order(published_at: :desc) }

  def draft?     = status == "draft"
  def scheduled? = status == "scheduled"
  def published? = status == "published"
  def partial?   = status == "partial"
  def failed?    = status == "failed"

  def short_summary
    body.to_s.truncate(80)
  end

  private

  def target_platforms_known
    bad = Array(target_platforms) - SocialAccount::PLATFORMS
    errors.add(:target_platforms, "unknown platform(s): #{bad.join(', ')}") if bad.any?
    errors.add(:target_platforms, "pick at least one platform") if Array(target_platforms).empty?
  end

  def scheduled_for_in_future
    return if scheduled_for.present? && scheduled_for > 30.seconds.ago
    errors.add(:scheduled_for, "must be in the future") if scheduled_for.blank? || scheduled_for <= 30.seconds.ago
  end
end
