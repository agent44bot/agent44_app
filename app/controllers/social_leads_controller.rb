# Human review actions for Echo's social-listening leads (see SocialLead /
# SocialListenJob). A lead is only ever dismissed or marked as replied by a
# person; nothing posts automatically. Membership-scoped + writers only.
class SocialLeadsController < ApplicationController
  before_action :set_lead

  def dismiss
    @lead.update!(status: "dismissed")
    redirect_back fallback_location: social_workspace_path(@workspace.slug), notice: "Dismissed."
  end

  def mark_sent
    @lead.update!(status: "sent", draft_reply: params[:draft_reply].presence || @lead.draft_reply)
    redirect_back fallback_location: social_workspace_path(@workspace.slug), notice: "Marked as replied."
  end

  def destroy
    @lead.destroy
    redirect_back fallback_location: social_workspace_path(@workspace.slug), notice: "Draft deleted."
  end

  private

  def set_lead
    # find_by! on the user's own workspaces is the authz: a non-member 404s
    # (not the /nykitchen prefix allow-list). Only writers can act.
    @workspace = Current.user.workspaces.find_by!(slug: params[:workspace_slug])
    return head(:forbidden) unless %w[owner admin editor].include?(@workspace.role_for(Current.user))
    @lead = @workspace.social_leads.find(params[:id])
  end
end
