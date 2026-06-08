# A single metered, billable action (a button click that has a price), logged
# now so we can bill it later. Kept generic so any feature can record usage:
#   UsageEvent.record!(workspace:, user:, kind: "report.on_demand")
#
# We are NOT charging yet (track-only); Invoice.generate_for can later fold a
# period's usage_events into its raw fleet cost the same way it sums AI + smoke.
class UsageEvent < ApplicationRecord
  belongs_to :workspace
  belongs_to :user, optional: true

  serialize :metadata, coder: JSON

  validates :kind, presence: true
  validates :quantity, :unit_cents, numericality: { greater_than_or_equal_to: 0 }

  scope :in_period, ->(range) { where(created_at: range) }
  scope :of_kind,   ->(kind) { where(kind: kind) }

  # Log one metered action. Defaults to a single penny so "track, don't charge
  # yet" still records the intended price for when billing turns on.
  def self.record!(workspace:, kind:, user: nil, quantity: 1, unit_cents: 1, metadata: {})
    create!(workspace: workspace, user: user, kind: kind,
            quantity: quantity, unit_cents: unit_cents, metadata: metadata || {})
  end

  def metadata
    super || {}
  end

  def cost_cents
    quantity.to_i * unit_cents.to_i
  end
end
