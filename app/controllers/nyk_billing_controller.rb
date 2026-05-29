# Lora-facing billing view for NYK AI usage. Gated behind ENV
# NYK_BILLING_VISIBLE so we can stand it up internally before exposing
# it to her — admins always see it regardless of the flag.
class NykBillingController < ApplicationController
  before_action :require_authentication
  before_action :require_visible
  before_action :require_site_admin, only: %i[update_rate update_pricing]

  # Customer-view markup. NYK_BASE_FEE_DOLLARS + (raw cost × NYK_RAW_MULTIPLIER).
  # Defaults match the current pricing thesis: $50/mo base + 3× raw.
  DEFAULT_BASE_FEE   = 50.0
  DEFAULT_MULTIPLIER = 3.0

  def show
    now = Time.zone.now
    @month_start = now.beginning_of_month
    @workspace = Workspace.find_by(slug: "nykitchen")
    @test_rate = @workspace&.effective_test_rate || SmokeTestRun::COST_PER_MINUTE

    nyk_logs_month = AiCallLog.where(source: AiCallLog::NYK_SOURCES).where("created_at >= ?", @month_start)
    @summary = AiCallLog.summary_by_source(nyk_logs_month)
    @ai_total   = AiCallLog.total_cost_dollars(nyk_logs_month)
    @ai_calls   = nyk_logs_month.count
    @recent     = nyk_logs_month.order(created_at: :desc).limit(20)

    smoke_runs_month = SmokeTestRun.nyk.where("started_at >= ?", @month_start)
    @smoke_count    = smoke_runs_month.count
    @smoke_minutes  = (smoke_runs_month.sum(:duration_ms) / 60_000.0).round
    @smoke_cost     = smoke_runs_month.sum(:cost_dollars).to_f

    @raw_total       = @ai_total + @smoke_cost
    @customer_view   = params[:view] == "customer"
    @raw_multiplier  = (ENV["NYK_RAW_MULTIPLIER"].presence || DEFAULT_MULTIPLIER).to_f
    fee_default      = (ENV["NYK_BASE_FEE_DOLLARS"].presence || DEFAULT_BASE_FEE).to_f
    @base_fee_waived = @workspace&.base_fee_waived? || false
    @base_fee        = @workspace ? @workspace.effective_base_fee(fee_default) : fee_default
    @discount_percent  = (@workspace&.discount_percent || 0).to_f
    @customer_subtotal = @base_fee + (@raw_total * @raw_multiplier)
    @discount_amount   = (@customer_subtotal * @discount_percent / 100.0).round(2)
    @customer_total    = (@customer_subtotal - @discount_amount).round(2)
    @month_total       = @customer_view ? @customer_total : @raw_total
  end

  # Site-admin only: set this workspace's $/min test-run rate, then re-price all
  # of its existing smoke runs so billing + the agent salaries reflect it at once.
  def update_rate
    ws = Workspace.find_by(slug: "nykitchen")
    rate = params[:test_cost_per_minute].to_f
    return redirect_to(nyk_billing_path, alert: "Enter a positive rate.") if ws.nil? || rate <= 0

    ws.update!(test_cost_per_minute: rate)
    repriced = 0
    SmokeTestRun.nyk.where.not(duration_ms: nil).find_each do |r|
      r.update_columns(cost_dollars: ((r.duration_ms / 60_000.0) * rate).round(6))
      repriced += 1
    end
    redirect_to nyk_billing_path, notice: "Test-run rate set to $#{format('%.5f', rate)}/min. Re-priced #{repriced} runs."
  end

  # Site-admin only: the customer-facing pricing knobs (flat fee, waive, discount).
  # Display-only — no run re-pricing needed.
  def update_pricing
    ws = Workspace.find_by(slug: "nykitchen")
    return redirect_to(nyk_billing_path, alert: "Workspace not found.") unless ws
    ws.update!(
      base_fee_dollars: params[:base_fee_dollars].presence&.to_f,
      base_fee_waived:  params[:base_fee_waived] == "1",
      discount_percent: (params[:discount_percent].presence&.to_f || 0)
    )
    redirect_to nyk_billing_path(view: "customer"), notice: "Customer pricing updated."
  end

  private

  def require_site_admin
    return if Current.user&.admin?
    redirect_to nyk_billing_path, alert: "Only the site admin can change the rate."
  end

  def require_visible
    return if Current.user&.admin? # site admin always
    ws = Workspace.find_by(slug: "nykitchen")
    return if ws&.manager?(Current.user) # NYK workspace owner/admin (e.g. Lora)
    redirect_to "/nykitchen", alert: "Not available."
  end
end
