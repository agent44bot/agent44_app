class KitchenController < ApplicationController
  # Only the hub is publicly viewable — anonymous visitors can preview the
  # NY Kitchen agents fleet (so Lora can share /nykitchen with her boss),
  # but every card click requires sign-in/sign-up. The four agent pages
  # (list/test/data + the /nykitchen/social alias which routes to
  # workspaces#social), the POST endpoints (social_post_log, enhance_post,
  # send_to_workspace, trigger_smoke), and the digest/download actions all
  # gate via the default require_authentication.
  allow_unauthenticated_access only: [:hub]

  before_action :set_common_view_state, only: %i[hub list test data]

  def hub
    # Legacy bookmarks: /nykitchen?tab=smoke → /nykitchen/test, ?tab=scrapes → /nykitchen/data.
    case params[:tab]
    when "smoke"   then return redirect_to(nyk_test_path(status: params[:status]), status: 301)
    when "scrapes" then return redirect_to(nyk_data_path, status: 301)
    when "list"    then return redirect_to(nyk_list_path, status: 301)
    end
    load_hub_summary
    @nyk_workspace = nyk_workspace_for(Current.user)
    # Team management is rendered below the agent cards for members; load
    # the workspace data so the partial can render.
    load_nyk_team_data if @nyk_workspace
    render "admin/kitchen/hub", layout: "application"
  end

  def list
    @sendable_workspaces = sendable_workspaces_for(Current.user)
    load_events_data
    render "admin/kitchen/list", layout: "application"
  end

  def test
    load_smoke_data
    render "admin/kitchen/test", layout: "application"
  end

  def data
    load_scrape_data
    render "admin/kitchen/data", layout: "application"
  end

  def digest
    @digest = KitchenTicketDigest.find(params[:id])
    @snapshot = @digest.kitchen_snapshot
    @can_see_pricing = Workspace.find_by(slug: "nykitchen")&.pricing_visible_for?(Current.user) || false
    render layout: "application"
  end

  def download_smoke_page_source
    run = SmokeTestRun.find(params[:id])
    return head :not_found unless run.page_source.attached?
    redirect_to rails_blob_url(run.page_source, disposition: "attachment"), allow_other_host: true
  end

  def download_smoke_trace
    run = SmokeTestRun.find(params[:id])
    return head :not_found unless run.trace.attached?
    redirect_to rails_blob_url(run.trace, disposition: "attachment"), allow_other_host: true
  end

  def social_post_log
    log = SocialPostLog.find_or_initialize_by(event_url: params[:event_url])

    if params[:action_type] == "copy"
      log.copied_at ||= Time.current
    elsif params[:action_type] == "posted"
      log.posted_at = params[:posted] == "true" ? (log.posted_at || Time.current) : nil
    elsif params[:action_type] == "save_text"
      log.enhanced_text = params[:text]
    end

    log.save!
    render json: { copied_at: log.copied_at, posted_at: log.posted_at }
  end

  def enhance_post
    api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
    if api_key.blank?
      render json: { error: "no_api_key", message: "API key not configured" }, status: 422
      return
    end

    client = Anthropic::Client.new(api_key: api_key)
    prompt = build_enhance_prompt(params[:draft], params[:event_name], params[:event_description], params[:event_date], params[:event_price], params[:idea])

    response = client.messages.create(
      model: "claude-haiku-4-5-20251001",
      max_tokens: 600,
      messages: [ { role: "user", content: prompt } ]
    )

    enhanced = response.content.first.text

    AiCallLogger.log!(response, model: "claude-haiku-4-5-20251001", source: "nyk_enhance", user: Current.user)

    log = SocialPostLog.find_or_initialize_by(event_url: params[:event_url])
    log.enhanced_text = enhanced
    log.save!

    Current.user&.increment!(:ai_enhances_used)

    render json: { enhanced: enhanced }
  rescue Anthropic::Errors::APIError => e
    render json: { error: "api_error", message: e.message }, status: 502
  end

  # POST /nykitchen/send_to_workspace — admin clicks "Send to workspace" on a
  # NYK event preview; we create a WorkspaceDraft on the workspace the admin
  # picked (workspace_slug param) with the current (possibly AI-enhanced)
  # preview text, target all that workspace's connected platforms, status=draft
  # so the admin can review + post from /workspaces/:slug.
  def send_to_workspace
    return render(json: { error: "sign_in_required" }, status: :unauthorized) unless Current.user

    slug = params[:workspace_slug].to_s
    # Membership IS the authorization — user.workspaces only includes
    # workspaces they're a member of, so a non-member lookup returns nil
    # and we 404 below.
    ws   = Current.user.workspaces.find_by(slug: slug)
    return render json: { error: "workspace_not_found", slug: slug }, status: :not_found unless ws

    body = params[:text].to_s.strip
    return render json: { error: "empty" }, status: :unprocessable_entity if body.blank?

    # Save the draft against whichever platforms the workspace has, even
    # if some/all need re-auth — the user fixes auth on the draft edit
    # page before publish. Only reject if there are zero platforms at all.
    platforms = ws.social_accounts.pluck(:platform).uniq
    return render json: { error: "no_platforms" }, status: :unprocessable_entity if platforms.empty?

    draft = ws.workspace_drafts.create!(
      author:           Current.user,
      body:             body,
      target_platforms: platforms,
      image_url:        params[:image_url].to_s.presence,
      source_url:       params[:event_url].to_s.presence,
      status:           "draft"
    )

    # Drop Lora straight into the draft's edit page so she can tweak +
    # publish without an intermediate scroll. /workspaces/:slug/drafts/:id/edit
    # works for any workspace; the NYK alias isn't needed here because
    # the URL itself is workspace-scoped already.
    target_url = edit_workspace_draft_path(workspace_slug: ws.slug, id: draft.id)
    render json: {
      ok:             true,
      draft_id:       draft.id,
      workspace_url:  target_url,
      workspace_name: ws.name
    }
  rescue => e
    Rails.logger.error("send_to_workspace failed: #{e.class}: #{e.message}")
    render json: { error: "server_error", message: e.message }, status: :internal_server_error
  end

  def trigger_smoke
    token = ENV["GITHUB_PAT"]
    if token.blank?
      render json: { error: "GITHUB_PAT not configured" }, status: 500
      return
    end

    uri = URI("https://api.github.com/repos/agent44bot/agent44_app/dispatches")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 10

    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{token}"
    req["Accept"] = "application/vnd.github+json"
    req["Content-Type"] = "application/json"
    req.body = { event_type: "smoke-nyk" }.to_json

    res = http.request(req)

    if res.is_a?(Net::HTTPSuccess) || res.code == "204"
      render json: {
        ok: true,
        workflow_url: "https://github.com/agent44bot/agent44_app/actions/workflows/smoke-nyk.yml"
      }
    else
      render json: { error: "GitHub dispatch failed (#{res.code})" }, status: 502
    end
  rescue => e
    render json: { error: e.message }, status: 500
  end

  private

  # Per-event "this URL has been queued/posted in a workspace" lookup, for
  # the kitchen list. Returns a hash keyed by event URL with the row state:
  #   { kind: :posted, time:, platforms: [..], workspace_name: }
  #   { kind: :drafted, time:, workspace_name: }
  # nil for events with no draft/post in any workspace the user belongs to.
  def workspace_status_for(user, urls)
    return {} unless user&.admin? && urls.any?

    ws_ids = user.workspaces.pluck(:id)
    return {} if ws_ids.empty?

    posts  = WorkspacePost.where(workspace_id: ws_ids, status: "posted", source_url: urls).includes(:workspace)
    drafts = WorkspaceDraft.where(workspace_id: ws_ids, source_url: urls).includes(:workspace)

    status = {}
    urls.each do |url|
      url_posts = posts.select  { |p| p.source_url == url }
      if url_posts.any?
        latest = url_posts.max_by { |p| p.posted_at || p.created_at }
        status[url] = {
          kind:           :posted,
          time:           latest.posted_at || latest.created_at,
          platforms:      url_posts.map(&:platform).uniq.sort,
          workspace_name: latest.workspace.name,
          workspace_slug: latest.workspace.slug
        }
        next
      end
      url_drafts = drafts.select { |d| d.source_url == url }
      if url_drafts.any?
        latest = url_drafts.max_by(&:created_at)
        status[url] = {
          kind:           :drafted,
          time:           latest.created_at,
          workspace_name: latest.workspace.name,
          workspace_slug: latest.workspace.slug
        }
      end
    end
    status
  end

  # Workspaces the signed-in user can pick as the destination for the
  # Social Agent handoff. We require *any* social account (so the
  # workspace looks like a real social destination), not an active one
  # — drafts created from the handoff are persisted in 'draft' status;
  # token validity is only enforced at publish time on the draft edit
  # page. This means an expired-token workspace still shows up here
  # and the user can keep stacking drafts while they re-auth.
  # Sort: workspaces whose slug includes "kitchen" first (so the NYK
  # page naturally defaults to the NYK workspace), then alphabetical.
  def sendable_workspaces_for(user)
    return [] unless user
    user.workspaces
        .joins(:social_accounts)
        .distinct
        .sort_by { |ws| [ws.slug.include?("kitchen") ? 0 : 1, ws.name.to_s.downcase] }
  end

  def set_common_view_state
    @admin = authenticated? && (Current.user.admin? || Current.user.reviewer?)
    @can_see_pricing = Workspace.find_by(slug: "nykitchen")&.pricing_visible_for?(Current.user) || false
  end

  # The user's NYK-flavored workspace, if any — backs the Social Agent card
  # on the hub. Falls back to nil; the card then links to /workspaces.
  def nyk_workspace_for(user)
    return nil unless user
    user.workspaces.find { |w| w.slug.to_s.include?("kitchen") || w.name.to_s.downcase.include?("kitchen") }
  end

  # Loads the locals needed by workspaces/_team partial when rendering on
  # the NYK hub. Only called when @nyk_workspace is present (i.e. the
  # signed-in user is a member of the NY Kitchen workspace).
  def load_nyk_team_data
    @nyk_memberships     = @nyk_workspace.memberships.includes(:user).order(:created_at)
    @nyk_invitations     = @nyk_workspace.invitations.pending.order(created_at: :desc)
    @nyk_social_accounts = @nyk_workspace.social_accounts.order(:platform, :handle)
    @nyk_my_role         = @nyk_workspace.role_for(Current.user)
  end

  # List Agent data — events, weeks, filter counts, workspace status.
  def load_events_data
    snapshot = KitchenSnapshot.latest
    if snapshot
      @events = snapshot.kitchen_events.upcoming.order(:start_at)
      today = Date.today
      days_until_sunday = (7 - today.cwday) % 7
      this_sunday = today + days_until_sunday

      # Build dynamic weekly buckets covering all events
      @weeks = []
      labels = [ "Current Week", "Next Week" ]
      last_event_date = @events.last&.start_at&.to_date || today
      week_start = today
      week_end = this_sunday

      while week_start <= last_event_date
        week_events = @events.select { |e| (week_start..week_end).cover?(e.start_at.to_date) }
        label = @weeks.size < labels.size ? labels[@weeks.size] : week_start.strftime("Week of %b %-d")
        @weeks << { label: label, events: week_events, expanded: @weeks.size < 2 }
        week_start = week_end + 1
        week_end = week_start + 6
      end

      @total = @events.size
      @sold_out = @events.count(&:sold_out?)
      @last_updated = snapshot.taken_on

      statuses = @events.map(&:availability_status)
      @filter_counts = {
        "all"     => statuses.size,
        "instock" => statuses.count("instock"),
        "limited" => statuses.count("limited"),
        "soldout" => statuses.count("soldout"),
        "closed"  => statuses.count("closed"),
        "other"   => statuses.count("other")
      }

      event_urls = @events.map(&:url)
      @post_logs = SocialPostLog.where(event_url: event_urls).index_by(&:event_url)
      @workspace_status_by_url = workspace_status_for(Current.user, event_urls)
    else
      @events = []
      @weeks = []
      @total = 0
      @sold_out = 0
      @workspace_status_by_url = {}
      @filter_counts = { "all" => 0, "instock" => 0, "limited" => 0, "soldout" => 0, "closed" => 0, "other" => 0 }
      @post_logs = {}
    end
  end

  # Test Agent data — smoke runs, failure stats, daily-failure chart.
  def load_smoke_data
    nav_scope = SmokeTestRun.nyk_nav

    # Test page filter: status pill (All / Passed / Failed). The
    # "last 30 days" failure-rate card is fixed; the table is windowed to
    # 30 days too so it stays in sync with the card.
    @smoke_status = %w[passed failed].include?(params[:status]) ? params[:status] : "all"
    @smoke_days   = 30

    windowed_scope = nav_scope.where("started_at >= ?", @smoke_days.days.ago)
    table_scope    = case @smoke_status
                     when "passed" then windowed_scope.where(status: "passed")
                     when "failed" then windowed_scope.where(status: "failed")
                     else               windowed_scope
                     end

    smoke_table_limit = 1000
    @smoke_runs = table_scope.recent.with_attached_video.with_attached_thumbnail.limit(smoke_table_limit)
    @smoke_runs_truncated = table_scope.count > smoke_table_limit

    # All-time stats — independent of filters, so Lora always sees the running totals.
    @smoke_runs_total_count   = nav_scope.count
    @smoke_runs_total_cost    = nav_scope.sum(:cost_dollars)
    @smoke_runs_total_minutes = (nav_scope.sum(:duration_ms) / 60_000.0).round
    @smoke_failed_count       = nav_scope.where(status: "failed").count
    @smoke_failure_rate       = @smoke_runs_total_count.zero? ? 0.0 :
      (@smoke_failed_count.to_f / @smoke_runs_total_count * 100).round(1)

    # Window stats — drive the second failure-rate card; status filter excluded
    # (otherwise filtering to "failed" would always show 100%).
    total_window  = windowed_scope.count
    failed_window = windowed_scope.where(status: "failed").count
    @smoke_runs_count_window   = total_window
    @smoke_failed_count_window = failed_window
    @smoke_failure_rate_window = total_window.zero? ? 0.0 :
      (failed_window.to_f / total_window * 100).round(1)

    # Daily buckets for the failures-by-day chart. Pluck + group in Ruby so we
    # don't have to fight SQLite/Postgres differences in DATE() + timezone.
    day_buckets = Hash.new { |h, k| h[k] = { total: 0, failed: 0 } }
    windowed_scope.pluck(:started_at, :status).each do |started_at, status|
      d = started_at.in_time_zone.to_date
      day_buckets[d][:total]  += 1
      day_buckets[d][:failed] += 1 if status == "failed"
    end
    today = Time.zone.today
    @smoke_chart = (0...@smoke_days).map do |i|
      date   = today - (@smoke_days - 1 - i)
      bucket = day_buckets[date]
      { date: date, total: bucket[:total], failed: bucket[:failed] }
    end
  end

  # Data Agent data — scrape runs and per-day event summary.
  def load_scrape_data
    scrape_scope = SmokeTestRun.nyk_scrape

    @scrape_runs = scrape_scope.recent.with_attached_video.with_attached_thumbnail.limit(100)
    @scrape_runs_total_count   = scrape_scope.count
    @scrape_runs_total_cost    = scrape_scope.sum(:cost_dollars)
    @scrape_runs_total_minutes = (scrape_scope.sum(:duration_ms) / 60_000.0).round

    # Per-day event counts. KitchenSnapshot is unique on taken_on, so multiple
    # scrapes the same day all reflect that day's snapshot.
    scrape_days = @scrape_runs.map { |r| r.started_at.to_date }.uniq
    @scrape_day_summary = KitchenSnapshot.where(taken_on: scrape_days)
      .includes(:kitchen_events)
      .each_with_object({}) do |snap, h|
        events = snap.kitchen_events.to_a
        h[snap.taken_on] = {
          total:     events.size,
          available: events.count { |e| %w[instock limited].include?(e.availability_status) },
          soldout:   events.count { |e| %w[soldout closed].include?(e.availability_status) }
        }
      end
  end

  # Hub summary — just the headline numbers each card displays. Pulls from the
  # same scopes as the detail pages but skips the heavy joins/snapshot loads.
  def load_hub_summary
    snapshot = KitchenSnapshot.latest
    @hub_events_total    = snapshot ? snapshot.kitchen_events.upcoming.count : 0
    @hub_events_updated  = snapshot&.taken_on

    nav    = SmokeTestRun.nyk_nav
    scrape = SmokeTestRun.nyk_scrape

    # Most-recent row (incl. running rows) for presence-dot logic.
    @hub_smoke_last       = nav.recent.first
    # Most-recent FINISHED row for the headline "Passed N ago" line — we
    # don't want a momentary in-flight row to wipe out the last result.
    @hub_smoke_last_finished = nav.finished.recent.first
    @hub_smoke_total      = nav.finished.count
    @hub_smoke_failed_30d = nav.where("started_at >= ?", 30.days.ago).where(status: "failed").count
    @hub_smoke_runs_30d   = nav.finished.where("started_at >= ?", 30.days.ago).count
    @hub_smoke_fail_rate_30d = @hub_smoke_runs_30d.zero? ? 0.0 :
      (@hub_smoke_failed_30d.to_f / @hub_smoke_runs_30d * 100).round(1)
    @hub_smoke_cost_total    = nav.sum(:cost_dollars)
    @hub_smoke_total_minutes = (nav.sum(:duration_ms) / 60_000.0).round

    @hub_scrape_last         = scrape.recent.first
    @hub_scrape_last_finished = scrape.finished.recent.first
    @hub_scrape_total        = scrape.finished.count
    @hub_scrape_cost_total   = scrape.sum(:cost_dollars)
    @hub_scrape_total_minutes = (scrape.sum(:duration_ms) / 60_000.0).round

    @hub_agent_status = {
      list:   list_agent_status,
      test:   test_agent_status,
      data:   data_agent_status,
      social: social_agent_status
    }
  end

  # Agent presence: :running (pulsing green dot, run in flight),
  # :failed (solid red dot, last finished run failed — sustained until a
  # passing run lands), :on_cadence (solid green, within cadence window),
  # :stale (gray, no recent run).
  TEST_CADENCE = 90.minutes # smoke runs every ~hour, +30min slack
  DATA_CADENCE = 4.hours    # scrapes every 3 hours, +1h slack
  LIST_CADENCE = 30.hours   # snapshot taken_on is per-day, allow a stale day before going gray
  SOCIAL_CADENCE = 7.days

  def list_agent_status
    return :stale unless @hub_events_updated
    age = Date.current - @hub_events_updated
    age <= (LIST_CADENCE / 1.day) ? :on_cadence : :stale
  end

  def test_agent_status
    agent_status_from_runs(@hub_smoke_last, @hub_smoke_last_finished, TEST_CADENCE)
  end

  def data_agent_status
    agent_status_from_runs(@hub_scrape_last, @hub_scrape_last_finished, DATA_CADENCE)
  end

  def social_agent_status
    return :stale unless @nyk_workspace
    last = @nyk_workspace.workspace_posts.maximum(:posted_at)
    return :stale unless last
    Time.current - last < SOCIAL_CADENCE ? :on_cadence : :stale
  end

  # Smoke/scrape presence: a SmokeTestRun row exists for each kickoff.
  # - last_run: most recent row (may be status=running, i.e. in flight)
  # - last_finished: most recent passed/failed row, ignoring running ones
  # - cadence: how recently a finished run must have landed to count as
  #   "on cadence" (i.e. healthy enough to be solid green)
  def agent_status_from_runs(last_run, last_finished, cadence)
    return :stale  unless last_run || last_finished
    return :running if last_run&.running?
    return :failed  if last_finished&.failed?
    return :stale   unless last_finished
    Time.current - last_finished.started_at < cadence ? :on_cadence : :stale
  end

  def build_enhance_prompt(draft, name, description, date, price, idea = nil)
    idea_block = if idea.to_s.strip.present?
      <<~IDEA

        The user has a specific angle they want you to take with this post. Use this as your primary creative direction — let it shape the hook, the framing, and the tone:
        "#{idea.to_s.strip}"
      IDEA
    end

    <<~PROMPT
      You are a social media copywriter for New York Kitchen, a beloved culinary education center in Canandaigua in the Finger Lakes region of New York.

      Rewrite this Instagram post draft to be more engaging, creative, and compelling. Make it feel personal and exciting — not corporate or generic.

      Guidelines:
      - Keep it concise (under 300 words)
      - Use emojis naturally but don't overdo it
      - Reference seasonal/timely food trends, holidays, or cultural moments if relevant to the class topic
      - Add a creative hook or storytelling angle in the first line to stop the scroll
      - Keep the essential details (date, time, price, location, booking link)
      - Keep the hashtags at the end
      - Maintain the urgency/availability messaging
      - Write in a warm, inviting tone — like a friend telling you about something amazing
      #{idea_block}
      Class name: #{name}
      Date: #{date}
      Price: $#{price}
      Description: #{description}

      Original draft:
      #{draft}

      Return ONLY the enhanced post text, ready to paste into Instagram. No explanations or commentary.
    PROMPT
  end
end
