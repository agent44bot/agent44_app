# Lora-facing billing view for NYK AI usage. Gated behind ENV
# NYK_BILLING_VISIBLE so we can stand it up internally before exposing
# it to her — admins always see it regardless of the flag.
class NykBillingController < ApplicationController
  before_action :require_authentication
  before_action :require_visible

  # Customer-view markup. NYK_BASE_FEE_DOLLARS + (raw cost × NYK_RAW_MULTIPLIER).
  # Defaults match the current pricing thesis: $50/mo base + 3× raw.
  DEFAULT_BASE_FEE   = 50.0
  DEFAULT_MULTIPLIER = 3.0

  def show
    now = Time.zone.now
    @month_start = now.beginning_of_month

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
    @base_fee        = (ENV["NYK_BASE_FEE_DOLLARS"].presence || DEFAULT_BASE_FEE).to_f
    @raw_multiplier  = (ENV["NYK_RAW_MULTIPLIER"].presence  || DEFAULT_MULTIPLIER).to_f
    @customer_total  = @base_fee + (@raw_total * @raw_multiplier)
    @month_total     = @customer_view ? @customer_total : @raw_total
  end

  private

  def require_visible
    return if Current.session&.user&.admin?
    return if ENV["NYK_BILLING_VISIBLE"].to_s == "true" && Current.session&.user&.kitchen_only?
    redirect_to "/nykitchen", alert: "Not available yet."
  end
end
