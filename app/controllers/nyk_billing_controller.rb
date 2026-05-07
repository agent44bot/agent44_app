# Lora-facing billing view for NYK AI usage. Gated behind ENV
# NYK_BILLING_VISIBLE so we can stand it up internally before exposing
# it to her — admins always see it regardless of the flag.
class NykBillingController < ApplicationController
  before_action :require_authentication
  before_action :require_visible

  def show
    now = Time.zone.now
    @month_start = now.beginning_of_month
    nyk_logs_month = AiCallLog.where(source: AiCallLog::NYK_SOURCES).where("created_at >= ?", @month_start)
    @summary = AiCallLog.summary_by_source(nyk_logs_month)
    @month_total = AiCallLog.total_cost_dollars(nyk_logs_month)
    @month_calls = nyk_logs_month.count
    @recent = nyk_logs_month.order(created_at: :desc).limit(20)
  end

  private

  def require_visible
    return if Current.session&.user&.admin?
    return if ENV["NYK_BILLING_VISIBLE"].to_s == "true" && Current.session&.user&.kitchen_only?
    redirect_to "/nykitchen", alert: "Not available yet."
  end
end
