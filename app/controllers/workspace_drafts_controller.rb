class WorkspaceDraftsController < ApplicationController
  before_action :load_workspace
  before_action :require_writer

  ALLOWED_IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  MAX_IMAGE_BYTES     = 5 * 1024 * 1024 # X's tweet-image cap

  def create
    body      = params[:body].to_s.strip
    platforms = Array(params[:target_platforms]).map(&:to_s) & SocialAccount::PLATFORMS
    intent    = params[:commit].to_s == "schedule" ? "schedule" : "save"

    if body.blank?
      return redirect_to social_workspace_path(@workspace.slug), alert: "Draft body can't be empty."
    end
    if platforms.empty?
      return redirect_to social_workspace_path(@workspace.slug), alert: "Pick at least one platform."
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
      redirect_to social_workspace_path(@workspace.slug), notice: msg
    else
      redirect_to social_workspace_path(@workspace.slug), alert: "Draft failed: #{draft.errors.full_messages.to_sentence}"
    end
  end

  def edit
    @draft = @workspace.workspace_drafts.find(params[:id])
    if @draft.published? || @draft.partial? || @draft.failed?
      redirect_to social_workspace_path(@workspace.slug), alert: "Can't edit a draft that's already been processed."
    end
  end

  def update
    draft = @workspace.workspace_drafts.find(params[:id])

    body      = params[:body].to_s.strip
    platforms = Array(params[:target_platforms]).map(&:to_s) & SocialAccount::PLATFORMS
    # Keep ?return_to through the validation bounces so the Back button still
    # points where the user came from (e.g. Sam's list via Draft Post).
    rt = params[:return_to].presence

    if body.blank?
      return redirect_to edit_workspace_draft_path(workspace_slug: @workspace.slug, id: draft.id, return_to: rt), alert: "Draft body can't be empty."
    end
    if platforms.empty?
      return redirect_to edit_workspace_draft_path(workspace_slug: @workspace.slug, id: draft.id, return_to: rt), alert: "Pick at least one platform."
    end

    if draft.update(body: body, target_platforms: platforms, image_url: params[:image_url].to_s.presence)
      attach_image!(draft, params[:image]) if params[:image].present?
      draft.image.purge if params[:remove_image] == "1" && draft.image.attached?
      return publish_draft(draft) if params[:commit] == "post"
      redirect_to social_workspace_path(@workspace.slug), notice: "Draft updated."
    else
      redirect_to edit_workspace_draft_path(workspace_slug: @workspace.slug, id: draft.id, return_to: rt),
                  alert: "Update failed: #{draft.errors.full_messages.to_sentence}"
    end
  end

  # POST /workspaces/:slug/drafts/from_image — Brian's core loop: upload a
  # photo, the AI agent captions it on-brand, and we drop him on the edit
  # screen to review the caption + image before posting (with the image) to X.
  def from_image
    upload = params[:image]
    if upload.blank?
      return redirect_to social_workspace_path(@workspace.slug), alert: "Pick an image first."
    end
    unless ALLOWED_IMAGE_TYPES.include?(upload.content_type)
      return redirect_to social_workspace_path(@workspace.slug), alert: "Image must be a JPEG, PNG, GIF, or WebP."
    end

    bytes = upload.read
    if bytes.bytesize > MAX_IMAGE_BYTES
      return redirect_to social_workspace_path(@workspace.slug), alert: "Image is too large (max 5MB)."
    end

    result = WorkspaceAi::Drafter
               .new(@workspace, user: current_user)
               .suggest(topic: params[:topic], image_data: bytes, image_media_type: upload.content_type)

    body = result.ok? ? result.text : "Add a caption for this photo."

    draft = @workspace.workspace_drafts.new(
      author:           current_user,
      body:             body,
      target_platforms: default_image_platforms,
      status:           "draft"
    )

    if draft.save
      attach_image!(draft, upload)
      notice = result.ok? ? "Caption drafted from your image. Review, then post." : "Image saved, but AI caption failed (#{result.error}). Write your own."
      redirect_to edit_workspace_draft_path(workspace_slug: @workspace.slug, id: draft.id), notice: notice
    else
      redirect_to social_workspace_path(@workspace.slug), alert: "Couldn't start a draft: #{draft.errors.full_messages.to_sentence}"
    end
  end

  # POST /workspaces/:slug/drafts/:id/rewrite — uses Claude to rewrite the
  # draft body (with an optional topic/instruction). Result is stashed in
  # flash and pre-fills the edit form so the user reviews before saving.
  def rewrite
    draft = @workspace.workspace_drafts.find(params[:id])
    existing = params[:body].to_s.strip.presence || draft.body

    result = WorkspaceAi::Drafter
               .new(@workspace, user: current_user)
               .suggest(topic: params[:topic], existing_draft: existing)

    edit_path = edit_workspace_draft_path(workspace_slug: @workspace.slug, id: draft.id, return_to: params[:return_to].presence)
    if result.ok?
      flash[:draft_text]  = result.text
      flash[:draft_topic] = params[:topic].to_s.strip.presence
      redirect_to edit_path, notice: "AI suggestion ready — review + save."
    else
      redirect_to edit_path, alert: "AI rewrite failed: #{result.error}"
    end
  end

  def destroy
    draft = @workspace.workspace_drafts.find(params[:id])
    draft.destroy!
    redirect_to social_workspace_path(@workspace.slug), notice: "Draft removed."
  end

  def publish
    draft = @workspace.workspace_drafts.find(params[:id])
    publish_draft(draft)
  end

  def suggest
    result = WorkspaceAi::Drafter
               .new(@workspace, user: current_user)
               .suggest(topic: params[:topic], existing_draft: params[:body])

    if result.ok?
      flash[:draft_text]  = result.text
      flash[:draft_topic] = params[:topic].to_s.strip.presence
      redirect_to social_workspace_path(@workspace.slug), notice: "Draft suggestion ready."
    else
      redirect_to social_workspace_path(@workspace.slug), alert: "AI assist failed: #{result.error}"
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

  def publish_draft(draft)
    if draft.published? || draft.partial? || draft.failed?
      return redirect_to social_workspace_path(@workspace.slug), alert: "Draft was already processed."
    end

    result = WorkspaceDrafts::Publisher.new(draft).call
    if result.all_ok?
      redirect_to social_workspace_path(@workspace.slug), notice: "Posted: #{result.successes.join(' · ')}"
    elsif result.all_bad?
      redirect_to social_workspace_path(@workspace.slug), alert: "All posts failed: #{result.failures.join(' · ')}"
    else
      redirect_to social_workspace_path(@workspace.slug),
                  alert: "Partial: posted to #{result.successes.size}, failed #{result.failures.size}. #{result.failures.join(' · ')}"
    end
  end

  def attach_image!(draft, upload)
    upload.rewind if upload.respond_to?(:rewind)
    draft.image.attach(io: upload, filename: upload.original_filename.presence || "image", content_type: upload.content_type)
  end

  # Default an image draft to X (the platform we upload native media to). If
  # X isn't connected, fall back to whatever the workspace has so the draft
  # still saves and the publish step surfaces any connection issue.
  def default_image_platforms
    connected = @workspace.social_accounts.pluck(:platform).uniq
    connected.include?("x") ? [ "x" ] : (connected.presence || [ "x" ])
  end

  def load_workspace
    @workspace = Workspace.find_by!(slug: params[:workspace_slug])
  end

  def require_writer
    membership = @workspace.memberships.find_by(user_id: current_user.id)
    return if membership&.writer?
    redirect_to social_workspace_path(@workspace.slug), alert: "Only workspace writers can draft."
  end

  def current_user
    Current.user
  end
end
