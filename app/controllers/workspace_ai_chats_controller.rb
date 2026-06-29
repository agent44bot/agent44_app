# Connection help chat on the Social Agent page. Any workspace member can ask
# how to connect / post to a platform; the reply comes from Claude Haiku via
# WorkspaceAi::ConnectHelper. Cost is logged against the workspace + user, and
# returned tiered by role: owner (and site admins) get raw + billed, admins get
# billed only (never our raw cost), editors/viewers get nothing.
class WorkspaceAiChatsController < ApplicationController
  before_action :load_workspace
  before_action :require_member

  def create
    platform = params[:platform].to_s
    unless WorkspaceAi::ConnectHelper::PLATFORM_FACTS.key?(platform)
      return render json: { ok: false, error: "Unknown platform." }, status: :unprocessable_entity
    end

    history = Array(params[:history]).map do |m|
      m = m.respond_to?(:to_unsafe_h) ? m.to_unsafe_h : m
      { "role" => m["role"].to_s, "content" => m["content"].to_s }
    end

    result = WorkspaceAi::ConnectHelper.new(@workspace, user: current_user)
                                       .answer(platform: platform, message: params[:message].to_s, history: history)

    unless result.ok?
      return render json: { ok: false, error: result.error }, status: :unprocessable_entity
    end

    render json: payload_with_cost(result)
  end

  private

  # Cost is tiered by workspace role: owner (and site admins) get raw + billed;
  # admins get billed only (never our raw cost / the multiplier); editors and
  # viewers get nothing. Billed = raw x the workspace usage multiplier.
  def payload_with_cost(result)
    payload     = { ok: true, reply: result.reply }
    role        = @workspace.role_for(current_user)
    raw_view    = current_user&.admin? || role == "owner"
    billed_view = raw_view || role == "admin"
    return payload unless billed_view

    mult = @workspace.effective_usage_multiplier
    payload[:month_billed] = workspace_month_cost * mult
    payload[:cost_billed]  = result.cost_dollars.to_f * mult
    if raw_view
      payload[:month_raw]  = workspace_month_cost
      payload[:cost_raw]   = result.cost_dollars.to_f
      payload[:multiplier] = mult
    end
    payload
  end

  def load_workspace
    @workspace = Workspace.find_by!(slug: params[:workspace_slug])
  end

  def require_member
    return if @workspace.member?(current_user)
    render json: { ok: false, error: "Not a member of this workspace." }, status: :forbidden
  end

  def workspace_month_cost
    AiCallLog.usage_rollup(AiCallLog.for_workspace(@workspace).this_month)[:cost_dollars]
  end

  def current_user
    Current.user
  end
end
