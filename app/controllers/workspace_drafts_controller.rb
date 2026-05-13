class WorkspaceDraftsController < ApplicationController
  before_action :load_workspace
  before_action :require_writer

  def suggest
    result = WorkspaceAi::Drafter
               .new(@workspace, user: current_user)
               .suggest(topic: params[:topic], existing_draft: params[:body])

    if result.ok?
      flash[:draft_text]  = result.text
      flash[:draft_topic] = params[:topic].to_s.strip.presence
      redirect_to workspace_path(@workspace.slug), notice: "Draft suggestion ready."
    else
      redirect_to workspace_path(@workspace.slug), alert: "AI assist failed: #{result.error}"
    end
  end

  private

  def load_workspace
    @workspace = Workspace.find_by!(slug: params[:workspace_slug])
  end

  def require_writer
    membership = @workspace.memberships.find_by(user_id: current_user.id)
    return if membership&.writer?
    redirect_to workspace_path(@workspace.slug), alert: "Only workspace writers can draft."
  end

  def current_user
    Current.session.user
  end
end
