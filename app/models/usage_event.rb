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

  # Flyer monetization: 44 cents per print-page open and per QR scan (Agent 44).
  FLYER_PRINT      = "flyer.print".freeze
  FLYER_SCAN       = "flyer.scan".freeze
  FLYER_KINDS      = [ FLYER_PRINT, FLYER_SCAN ].freeze
  FLYER_UNIT_CENTS = 44

  # Total flyer/scan revenue (dollars) for a workspace in a period.
  # Revenue = prints + scans in the period times the workspace's CURRENT rate,
  # so changing the flyer rate re-prices the whole period immediately (NYK sets
  # one rate; we don't honor each row's rate-at-the-time). Display-screen scans
  # never create a UsageEvent, so they're excluded here automatically.
  def self.flyer_revenue_dollars(workspace, range)
    return 0.0 unless workspace
    qty  = where(workspace: workspace, kind: FLYER_KINDS).in_period(range).sum(:quantity)
    rate = workspace.effective_flyer_unit_cents
    (qty.to_i * rate.to_i) / 100.0
  end

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
