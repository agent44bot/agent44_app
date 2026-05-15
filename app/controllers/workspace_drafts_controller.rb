class WorkspaceDraftsController < ApplicationController
  include FleetSocialAccess
  before_action :load_workspace
  before_action :require_writer

  def create
    body      = params[:body].to_s.strip
    platforms = Array(params[:target_platforms]).map(&:to_s) & SocialAccount::PLATFORMS
    intent    = params[:commit].to_s == "schedule" ? "schedule" : "save"

    if body.blank?
      return redirect_to workspace_path(@workspace.slug), alert: "Draft body can't be empty."
    end
    if platforms.empty?
      return redirect_to workspace_path(@workspace.slug), alert: "Pick at least one platform."
    end

    scheduled_for = parse_scheduled_for(params[:scheduled_for])

    draft = @workspace.workspace_drafts.new(
      author:           current_user,
      body:             body,
      target_platforms: platforms,
      scheduled_for:    intent == "schedule" ? scheduled_for : nil,
      status:           intent == "schedule" ? "scheduled" : "draft"
    )

    if draft.save
      msg = intent == "schedule" ? "Scheduled for #{draft.scheduled_for.in_time_zone(@workspace.timezone).strftime('%b %-d, %-l:%M %p %Z')}." : "Draft saved."
      redirect_to workspace_path(@workspace.slug), notice: msg
    else
      redirect_to workspace_path(@workspace.slug), alert: "Draft failed: #{draft.errors.full_messages.to_sentence}"
    end
  end

  def destroy
    draft = @workspace.workspace_drafts.find(params[:id])
    draft.destroy!
    redirect_to workspace_path(@workspace.slug), notice: "Draft removed."
  end

  def publish
    draft = @workspace.workspace_drafts.find(params[:id])
    if draft.published? || draft.partial? || draft.failed?
      return redirect_to workspace_path(@workspace.slug), alert: "Draft was already processed."
    end

    result = WorkspaceDrafts::Publisher.new(draft).call
    if result.all_ok?
      redirect_to workspace_path(@workspace.slug), notice: "Posted — #{result.successes.join(' · ')}"
    elsif result.all_bad?
      redirect_to workspace_path(@workspace.slug), alert: "All posts failed — #{result.failures.join(' · ')}"
    else
      redirect_to workspace_path(@workspace.slug),
                  alert: "Partial: posted to #{result.successes.size}, failed #{result.failures.size}. #{result.failures.join(' · ')}"
    end
  end

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

  # datetime-local form input gives a naive local string like "2026-05-15T09:00".
  # Interpret it in the workspace's timezone so a "9 AM" schedule means 9 AM
  # for the team that owns the workspace.
  def parse_scheduled_for(raw)
    return nil if raw.blank?
    Time.use_zone(@workspace.timezone) { Time.zone.parse(raw.to_s) }
  rescue ArgumentError
    nil
  end

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
