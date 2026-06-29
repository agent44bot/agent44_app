# Per-workspace AI usage + billing, visible to the workspace's owner/admin
# (Workspace#manager?). Mirrors the NY Kitchen billing page but scoped by
# workspace_id (so it works for any workspace, e.g. Gems of Eden) and without
# the NYK-only smoke-test costs. Pricing knobs are site-admin only.
class WorkspaceBillingController < ApplicationController
  before_action :require_authentication
  before_action :load_workspace
  before_action :require_manager
  before_action :require_site_admin, only: %i[update_pricing mark_invoice_paid]

  # Human labels for the per-feature usage table / line items.
  SOURCE_LABELS = { "workspace_ai_assist" => "Social Agent drafts" }.freeze

  def show
    # NY Kitchen has its own richer billing page (smoke tests, per-feature model
    # choice). Keep that the canonical NYK view.
    return redirect_to nyk_billing_path if @workspace.slug == "nykitchen"

    now = Time.zone.now
    @month_start = now.beginning_of_month

    logs_month = AiCallLog.for_workspace(@workspace)
                          .where("created_at >= ?", @month_start)
                          .order(created_at: :desc).to_a
    @summary       = AiCallLog.summary_by_source(logs_month)
    @model_summary = AiCallLog.summary_by_model(logs_month)
    @ai_total      = AiCallLog.total_cost_dollars(logs_month)
    @ai_calls      = logs_month.size
    @recent        = logs_month.first(20)
    @ai_trend      = AiCallLog.monthly_for_workspace(@workspace, months: 6, now: now)
    @ai_trend_max  = @ai_trend.map { |m| m[:cost_dollars] }.max.to_f

    @raw_total           = @ai_total
    @usage_multiplier    = @workspace.effective_usage_multiplier
    @base_fee_waived     = @workspace.base_fee_waived?
    @base_fee_configured = (@workspace.base_fee_dollars || 0.0).to_f
    @base_fee            = @base_fee_waived ? 0.0 : @base_fee_configured
    @discount_percent    = (@workspace.discount_percent || 0).to_f
    @subtotal            = @base_fee + (@raw_total * @usage_multiplier)
    @discount_amount     = (@subtotal * @discount_percent / 100.0).round(2)
    @month_total         = (@subtotal - @discount_amount).round(2)

    @invoices = Invoice.where(workspace_id: @workspace.id).recent.to_a

    # Selected model key per AI feature, for the owner/admin model toggle.
    @model_keys = WorkspaceAi::ModelChoice::FEATURES.keys.index_with do |feature|
      WorkspaceAi::ModelChoice.selected_key(@workspace, feature)
    end
  end

  # Owner/admin picks the Anthropic model (Haiku/Sonnet/Opus) for a workspace
  # AI feature. Pricing knobs stay site-admin only; the model is a manager call.
  def update_model
    feature = params[:feature].to_s
    key     = params[:model].to_s
    unless WorkspaceAi::ModelChoice::FEATURES.key?(feature) && AiModelChoice::KEYS.include?(key)
      return redirect_to billing_workspace_path(@workspace.slug), alert: "Could not update that model."
    end
    WorkspaceAi::ModelChoice.set(@workspace, feature, key)
    redirect_to billing_workspace_path(@workspace.slug),
                notice: "#{WorkspaceAi::ModelChoice::FEATURES[feature]} now uses #{AiModelChoice::OPTIONS[key][:label]}."
  end

  def update_pricing
    @workspace.update!(
      base_fee_dollars: params[:base_fee_dollars].presence&.to_f,
      base_fee_waived:  params[:base_fee_waived] == "1",
      discount_percent: (params[:discount_percent].presence&.to_f || 0),
      usage_multiplier: (params[:usage_multiplier].presence&.to_f || 1.0)
    )
    redirect_to billing_workspace_path(@workspace.slug), notice: "Pricing updated."
  end

  def mark_invoice_paid
    invoice = Invoice.find_by(id: params[:invoice_id], workspace_id: @workspace.id)
    return redirect_to billing_workspace_path(@workspace.slug), alert: "Invoice not found." unless invoice

    invoice.mark_paid! unless invoice.paid?
    redirect_to billing_workspace_path(@workspace.slug), notice: "Invoice for #{invoice.period_label} marked paid."
  end

  private

  def load_workspace
    @workspace = Workspace.find_by!(slug: params[:slug])
  end

  def require_manager
    return if @workspace.manager?(Current.user)
    redirect_to workspace_path(@workspace.slug), alert: "Only workspace owners and admins can view billing."
  end

  def require_site_admin
    return if Current.user&.admin?
    redirect_to billing_workspace_path(@workspace.slug), alert: "Only the site admin can change pricing."
  end
end
