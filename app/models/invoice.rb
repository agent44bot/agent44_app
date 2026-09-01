class Invoice < ApplicationRecord
  belongs_to :workspace

  STATUSES = %w[unpaid paid].freeze
  DEFAULT_MULTIPLIER = 2.0
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

  # Render a multiplier for customer-facing copy: "3" for a whole number, "2.5"
  # otherwise. Never use to_i on a multiplier in a view — it renders 2.5 as "2",
  # printing arithmetic that does not match the total beside it.
  def self.format_multiplier(value)
    number = value.to_f
    number == number.round ? number.round.to_s : number.to_s
  end

  def multiplier_label
    self.class.format_multiplier(multiplier)
  end

  def period_label
    period_start.strftime("%B %Y")
  end

  # --- Customer statement figures -------------------------------------------
  # The statement Lora gets is a budget document, not a bill: it has to answer
  # "what would this cost us next year?" So it prices the month at LIST (the
  # configured platform fee, even when waived, plus marked-up usage) and shows
  # the pilot credit that brings it down to what was actually charged.

  # What this month would cost with no pilot pricing applied.
  def list_price_dollars
    base_fee_configured_dollars + (usage_cost_dollars * multiplier.to_f)
  end

  # Everything the pilot is currently absorbing: the waived fee and the
  # discount, as one number. Never negative (a total above list would mean the
  # knobs changed mid-period, and a "credit" of -$4 helps nobody).
  def pilot_credit_dollars
    [ (list_price_dollars - total_dollars).round(2), 0.0 ].max
  end

  # Rolling list-price average across this invoice and the ones before it, so
  # the statement's budget line doesn't swing on a single quiet month. Falls
  # back to this month alone for a workspace's first invoice.
  def average_list_price_dollars(months: 3)
    recent = self.class.where(workspace_id: workspace_id)
                 .where(period_start: ..period_start)
                 .order(period_start: :desc)
                 .limit(months)
                 .to_a
    recent = [ self ] if recent.empty?
    (recent.sum(&:list_price_dollars) / recent.size).round(2)
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

    # NYK work we run for them and absorb (Echo's social listening). Frozen
    # onto the invoice at $0 so the customer statement shows what the fleet did
    # on their behalf, not just the billable slice. Scoped to the explicit
    # ABSORBED_NYK_SOURCES list rather than "every unbilled nyk_ source", which
    # would sweep in nyk_agent, our own admin dogfood traffic.
    unbilled = if nyk
      AiCallLog.summary_by_source(
        AiCallLog.where(source: AiCallLog::ABSORBED_NYK_SOURCES, created_at: range)
      )
    else
      {}
    end

    line_items = build_line_items(by_source, smoke_count, smoke_cost, unbilled)

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

  # Frozen per-line breakdown: one row per AI feature, plus a smoke-test line,
  # plus (NYK only) the AI work we ran on their behalf but absorb, at $0.
  # Costs are raw (pre-markup), matching the "AI usage" table on the billing
  # page. Human labels mirror the billing view's source mapping. Rows carry
  # "billed" => false when they are included at no charge; a row without the
  # key predates it and is billed, so older invoices still read correctly.
  def self.build_line_items(by_source, smoke_count, smoke_cost, unbilled = {})
    labels = {
      "nyk_enhance"        => "Enhance with AI button",
      "nyk_x_autopost"     => "Daily X autopost draft",
      "nyk_team_report"    => "Weekly team report",
      "nyk_grocery_list"   => "Grocery lists",
      "nyk_recipe_extract" => "Recipe import",
      "nyk_recipe_generate" => "Recipe generation (AI)",
      "nyk_receipt_extract" => "Receipt scanning",
      "nyk_ask"            => "Super Agent chat",
      "nyk_social_scout"   => "Echo social listening",
      "workspace_ai_assist" => "Social Agent drafts"
    }
    items = by_source.sort_by { |_, v| -v[:cost_dollars] }.map do |source, v|
      { "label" => labels[source] || source, "calls" => v[:calls],
        "cost_cents" => (v[:cost_dollars] * 100).round,
        "cost_dollars" => v[:cost_dollars].round(6) }
    end
    if smoke_count.positive? || smoke_cost.positive?
      items << { "label" => "Browser smoke tests", "calls" => smoke_count,
                 "cost_cents" => (smoke_cost * 100).round,
                 "cost_dollars" => smoke_cost.round(6) }
    end
    unbilled.sort_by { |_, v| -v[:calls] }.each do |source, v|
      items << { "label" => labels[source] || source, "calls" => v[:calls],
                 "cost_cents" => 0, "cost_dollars" => 0.0, "billed" => false }
    end
    items
  end

  # The line items the customer is actually charged for.
  def billed_line_items
    line_items.reject { |li| li["billed"] == false }
  end

  # Work we ran for them and absorbed (shown at no charge).
  def unbilled_line_items
    line_items.select { |li| li["billed"] == false }
  end

  # A line's metered cost. Prefers the full-precision figure written since the
  # itemized statement landed, falling back to the rounded cents on older rows.
  def self.line_cost_dollars(item)
    item["cost_dollars"] || (item["cost_cents"].to_f / 100.0)
  end

  # Metered cost per run/use on a line, for the statement's "rate each" column.
  def self.line_unit_dollars(item)
    calls = item["calls"].to_i
    return 0.0 if calls.zero?
    line_cost_dollars(item) / calls
  end

  # What the billed lines add up to before the markup. Uses the frozen lines so
  # the statement's column actually sums to the number printed under it.
  def metered_usage_dollars
    billed_line_items.sum { |li| self.class.line_cost_dollars(li) }.round(2)
  end
end
