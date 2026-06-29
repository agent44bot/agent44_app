class Invoice < ApplicationRecord
  belongs_to :workspace

  STATUSES = %w[unpaid paid].freeze
  DEFAULT_MULTIPLIER = 3.0
  DEFAULT_BASE_FEE   = 50.0

  validates :period_start, :period_end, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(period_start: :desc) }
  scope :unpaid, -> { where(status: "unpaid") }
  scope :paid,   -> { where(status: "paid") }

  serialize :line_items, coder: JSON

  def paid?
    status == "paid"
  end

  def mark_paid!
    update!(status: "paid", paid_at: Time.current)
  end

  def line_items
    super || []
  end

  # Dollar accessors (storage is integer cents).
  def base_fee_dollars;            base_fee_cents.to_i            / 100.0; end
  def base_fee_configured_dollars; base_fee_configured_cents.to_i / 100.0; end
  def usage_cost_dollars; usage_cost_cents.to_i / 100.0; end
  def subtotal_dollars;   subtotal_cents.to_i   / 100.0; end
  def discount_dollars;   discount_cents.to_i   / 100.0; end
  def total_dollars;      total_cents.to_i      / 100.0; end

  def period_label
    period_start.strftime("%B %Y")
  end

  # Build (or return the existing) frozen invoice for a workspace + calendar
  # month. `month` is any date within the target month. Idempotent: the unique
  # index on (workspace_id, period_start) means a re-run returns the row that's
  # already there rather than double-billing. Pricing is snapshotted from the
  # workspace's current knobs — once written, this row never recomputes.
  def self.generate_for(workspace, month)
    period_start = month.to_date.beginning_of_month
    period_end   = month.to_date.end_of_month

    existing = find_by(workspace_id: workspace.id, period_start: period_start)
    return existing if existing

    range = period_start.beginning_of_day..period_end.end_of_day

    # NY Kitchen bills its kitchen AI features (by source) plus browser smoke
    # tests with an ENV-global markup. Every other workspace bills its own
    # workspace-attributed AI usage (by workspace_id), no smoke tests, with its
    # own usage_multiplier.
    nyk = (workspace.slug == "nykitchen")

    ai_logs   = nyk ? AiCallLog.where(source: AiCallLog::NYK_SOURCES, created_at: range)
                    : AiCallLog.for_workspace(workspace).where(created_at: range)
    by_source = AiCallLog.summary_by_source(ai_logs)
    ai_cost   = AiCallLog.total_cost_dollars(ai_logs)

    smoke_cost  = 0.0
    smoke_count = 0
    if nyk
      smoke_runs  = SmokeTestRun.nyk.where(started_at: range)
      smoke_cost  = smoke_runs.sum(:cost_dollars).to_f
      smoke_count = smoke_runs.count
    end

    raw_total = ai_cost + smoke_cost

    multiplier  = nyk ? (ENV["NYK_RAW_MULTIPLIER"].presence || DEFAULT_MULTIPLIER).to_f
                      : workspace.effective_usage_multiplier
    # configured = the fee before waiving (mirrors the billing page's
    # @base_fee_configured); applied = what's actually charged (0 if waived).
    configured_fee = (workspace.base_fee_dollars || (nyk ? DEFAULT_BASE_FEE : 0.0)).to_f
    waived         = workspace.base_fee_waived?
    base_fee       = waived ? 0.0 : configured_fee
    discount_pc    = (workspace.discount_percent || 0).to_f

    subtotal = base_fee + (raw_total * multiplier)
    discount = (subtotal * discount_pc / 100.0).round(2)
    total    = (subtotal - discount).round(2)

    line_items = build_line_items(by_source, smoke_count, smoke_cost)

    create!(
      workspace:       workspace,
      period_start:    period_start,
      period_end:      period_end,
      base_fee_cents:            (base_fee       * 100).round,
      base_fee_configured_cents: (configured_fee * 100).round,
      base_fee_waived:           waived,
      usage_cost_cents:          (raw_total * 100).round,
      multiplier:       multiplier,
      discount_percent: discount_pc,
      subtotal_cents:   (subtotal * 100).round,
      discount_cents:   (discount * 100).round,
      total_cents:      (total    * 100).round,
      line_items:       line_items,
      status:           "unpaid"
    )
  end

  # Frozen per-line breakdown: one row per AI feature, plus a smoke-test line.
  # Costs are raw (pre-markup), matching the "AI usage" table on the billing
  # page. Human labels mirror the billing view's source mapping.
  def self.build_line_items(by_source, smoke_count, smoke_cost)
    labels = {
      "nyk_enhance"        => "Enhance with AI button",
      "nyk_x_autopost"     => "Daily X autopost draft",
      "nyk_team_report"    => "Weekly team report",
      "nyk_grocery_list"   => "Grocery lists",
      "nyk_recipe_extract" => "Recipe import",
      "nyk_recipe_generate" => "Recipe generation (AI)",
      "nyk_receipt_extract" => "Receipt scanning",
      "nyk_ask"            => "Super Agent chat",
      "workspace_ai_assist" => "Social Agent drafts"
    }
    items = by_source.sort_by { |_, v| -v[:cost_dollars] }.map do |source, v|
      { "label" => labels[source] || source, "calls" => v[:calls],
        "cost_cents" => (v[:cost_dollars] * 100).round }
    end
    if smoke_count.positive? || smoke_cost.positive?
      items << { "label" => "Browser smoke tests", "calls" => smoke_count,
                 "cost_cents" => (smoke_cost * 100).round }
    end
    items
  end
end
