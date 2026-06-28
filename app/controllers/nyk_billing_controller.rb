# Lora-facing billing view for NYK AI usage. Gated behind ENV
# NYK_BILLING_VISIBLE so we can stand it up internally before exposing
# it to her — admins always see it regardless of the flag.
class NykBillingController < ApplicationController
  before_action :require_authentication
  before_action :require_visible
  before_action :require_site_admin, only: %i[update_rate update_pricing mark_invoice_paid]

  # Customer-view markup. NYK_BASE_FEE_DOLLARS + (raw cost × NYK_RAW_MULTIPLIER).
  # Defaults match the current pricing thesis: $50/mo base + 3× raw.
  DEFAULT_BASE_FEE   = 50.0
  DEFAULT_MULTIPLIER = 3.0

  def show
    now = Time.zone.now
    @month_start = now.beginning_of_month
    @workspace = Workspace.find_by(slug: "nykitchen")
    @test_rate = @workspace&.effective_test_rate || SmokeTestRun::COST_PER_MINUTE

    # Load this month's NYK logs once (newest first) and derive everything from
    # that array, so the page makes one query here instead of load+count+recent.
    nyk_logs_month = AiCallLog.where(source: AiCallLog::NYK_SOURCES)
                              .where("created_at >= ?", @month_start)
                              .order(created_at: :desc).to_a
    @summary = AiCallLog.summary_by_source(nyk_logs_month)
    @model_summary = AiCallLog.summary_by_model(nyk_logs_month)
    # The selected model key per feature, for the radios in the AI usage table.
    @feature_model_keys = @summary.keys.index_with { |source| AiModelChoice.selected_key(source) }
    @ai_total   = AiCallLog.total_cost_dollars(nyk_logs_month)
    @ai_calls   = nyk_logs_month.size
    @recent     = nyk_logs_month.first(20)
    # 6-month AI-usage trend (raw cost per month, matching the per-source table
    # basis) so the direction of spend is visible, not just this month.
    @ai_trend     = AiCallLog.monthly_by_source(AiCallLog::NYK_SOURCES, months: 6, now: now)
    @ai_trend_max = @ai_trend.map { |m| m[:cost_dollars] }.max.to_f

    # One aggregate query for the month's smoke runs (count + minutes + cost).
    smoke = SmokeTestRun.nyk.where("started_at >= ?", @month_start)
                        .pick(Arel.sql("COUNT(*), COALESCE(SUM(duration_ms), 0), COALESCE(SUM(cost_dollars), 0)"))
    @smoke_count   = smoke[0].to_i
    @smoke_minutes = (smoke[1].to_f / 60_000.0).round
    @smoke_cost    = smoke[2].to_f

    @raw_total       = @ai_total + @smoke_cost
    # Customer view is the only view now — the old "Raw" tab exposed our cost
    # basis ("no markup, what we pay") to customers, so it was removed. The
    # admin cost readout lives on the hub salary badges / cost dashboard.
    @customer_view   = true
    @raw_multiplier  = (ENV["NYK_RAW_MULTIPLIER"].presence || DEFAULT_MULTIPLIER).to_f
    fee_default          = (ENV["NYK_BASE_FEE_DOLLARS"].presence || DEFAULT_BASE_FEE).to_f
    @base_fee_waived     = @workspace&.base_fee_waived? || false
    @base_fee_configured = (@workspace&.base_fee_dollars || fee_default).to_f # pre-waive value, for strike-through
    @base_fee            = @base_fee_waived ? 0.0 : @base_fee_configured
    @discount_percent  = (@workspace&.discount_percent || 0).to_f
    @customer_subtotal = @base_fee + (@raw_total * @raw_multiplier)
    @discount_amount   = (@customer_subtotal * @discount_percent / 100.0).round(2)
    @customer_total    = (@customer_subtotal - @discount_amount).round(2)
    @month_total       = @customer_view ? @customer_total : @raw_total

    @invoices = @workspace ? Invoice.where(workspace_id: @workspace.id).recent.to_a : []
  end

  # Site-admin only: flip an invoice to paid. Manual for now (no payment
  # processor) — we just record that NY Kitchen settled the month.
  def mark_invoice_paid
    invoice = Invoice.find(params[:id])
    invoice.mark_paid! unless invoice.paid?
    redirect_to nyk_billing_path, notice: "Invoice for #{invoice.period_label} marked paid."
  end

  # Manager (owner/admin) picks the Anthropic model for a feature from the AI
  # usage table. Gated by require_visible like the rest of the page.
  def update_model
    source = params[:source].to_s
    key    = params[:model].to_s
    unless AiModelChoice.controllable?(source) && AiModelChoice::KEYS.include?(key)
      return redirect_to nyk_billing_path, alert: "Could not update that model."
    end
    AiModelChoice.set(source, key)
    redirect_to nyk_billing_path, notice: "Model updated to #{AiModelChoice::OPTIONS[key][:label]}."
  end

  # Manager toggles whether opening a class with no recipe auto-drafts one with
  # AI (Setting default is on). Off reverts to the manual upload/paste form.
  def update_auto_recipe
    on = params[:auto_recipe_on_open] == "1"
    Setting.set("nyk:auto_recipe_on_open", on ? "true" : "false")
    redirect_to nyk_billing_path,
                notice: on ? "Auto-draft is on. Opening a class drafts a recipe with AI." :
                             "Auto-draft is off. Opening a class shows the manual recipe form."
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
