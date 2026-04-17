class SmokeTestRun < ApplicationRecord
  STATUSES = %w[passed failed].freeze
  COST_PER_MINUTE = 0.00044 # $0.00044/min

  has_one_attached :video
  has_one_attached :thumbnail

  validates :name, :status, :started_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  before_save :compute_cost, if: :duration_ms

  scope :recent, -> { order(started_at: :desc) }
  scope :for_name, ->(n) { where(name: n) }

  def passed?
    status == "passed"
  end

  def failed?
    status == "failed"
  end

  # Friendly duration string for display
  def duration_label
    return "—" unless duration_ms
    secs = duration_ms / 1000.0
    secs < 60 ? "#{secs.round(1)}s" : "#{(secs / 60).round(1)}m"
  end

  private

  def compute_cost
    minutes = duration_ms / 60_000.0
    self.cost_dollars = (minutes * COST_PER_MINUTE).round(6)
  end
end
