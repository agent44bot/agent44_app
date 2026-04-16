class SmokeTestRun < ApplicationRecord
  STATUSES = %w[passed failed].freeze

  validates :name, :status, :started_at, presence: true
  validates :status, inclusion: { in: STATUSES }

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
end
