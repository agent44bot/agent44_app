# Connection help chat on the Social Agent page. Any workspace member can ask
# how to connect / post to a platform; the reply comes from Claude Haiku via
# WorkspaceAi::ConnectHelper. Cost is logged against the workspace + user, and
# the running cost is only returned to managers (owner/admin) so members never
# see pricing (mirrors Workspace#pricing_visible_for?).
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

    payload = { ok: true, reply: result.reply }
    if @workspace.manager?(current_user)
      payload[:cost_dollars]        = result.cost_dollars
      payload[:workspace_month_cost] = workspace_month_cost
    end
    render json: payload
  end

  private

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
