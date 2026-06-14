class KitchenController < ApplicationController
  # Only the hub is publicly viewable — anonymous visitors can preview the
  # NY Kitchen agents fleet (so Lora can share /nykitchen with her boss),
  # but every card click requires sign-in/sign-up. The four agent pages
  # (list/test/data + the /nykitchen/social alias which routes to
  # workspaces#social), the POST endpoints (social_post_log, enhance_post,
  # send_to_workspace, trigger_smoke), and the digest/download actions all
  # gate via the default require_authentication.
  # display_print is public so the hub's "Print schedule" button can open it
  # in Safari (the only place iOS shows a print dialog — the in-app WKWebView
  # can't) without a login wall. Same public class data as :display, no
  # Claude/AI, so anonymous access is safe.
  allow_unauthenticated_access only: [ :hub, :display, :display_heartbeat, :display_print ]
  # The display screen pings this from a no-auth, no-CSRF-token page.
  skip_forgery_protection only: :display_heartbeat

  before_action :set_common_view_state, only: %i[hub list test data ask analyst grocery prices]
  # Super Agent (admin/customer-only): once App Review approved the app, we
  # re-added a gate on /nykitchen/ask so a random signup can't burn our Claude
  # credits via the chat. Admins, the App Store reviewer account, and members
  # of the nykitchen workspace (Lora's team) are allowed; everyone else 404s.
  # The POST action (ask_message) has its own inline check that returns JSON.
  before_action :require_nyk_super_agent_access, only: :ask
  # On-demand report actions are for NY Kitchen managers (Lora + Rich) only.
  before_action :require_nyk_manager, only: %i[generate_report send_smoke_report]

  def hub
    # Legacy bookmarks: /nykitchen?tab=smoke → /nykitchen/test, ?tab=scrapes → /nykitchen/data.
    case params[:tab]
    when "smoke"   then return redirect_to(nyk_test_path(status: params[:status]), status: 301)
    when "scrapes" then return redirect_to(nyk_data_path, status: 301)
    when "list"    then return redirect_to(nyk_list_path, status: 301)
    end
    load_hub_summary
    @smoke_alert  = smoke_alert_for(Current.user)
    @daily_prompt = morning_prompt_for(Current.user)
    @nyk_workspace = nyk_workspace_for(Current.user)
    # Cellar (storage-room inventory) card stats — live bottle count + low flags.
    inv_on_hand = InventoryItem.on_hand_by_item
    @hub_inventory_units = inv_on_hand.values.sum
    @hub_inventory_low   = InventoryItem.where.not(par_level: nil).count { |i| i.low_stock?(inv_on_hand[i.id].to_i) }
    # Per-agent "salary" (this month's tokens + cost). Owner/admin only.
    @hub_salary = hub_salary_by_agent if @can_see_pricing
    # Most-opened cards rise to the top (CSS order); needs load_hub_summary
    # to have set @hub_agent_status so failed agents can jump the queue.
    @hub_card_order = hub_card_order
    # Team management is rendered below the agent cards for members; load
    # the workspace data so the partial can render.
    load_nyk_team_data if @nyk_workspace
    render "admin/kitchen/hub", layout: "application"
  end

  def list
    @sendable_workspaces = sendable_workspaces_for(Current.user)
    # Recipe handout per class (keyed by event URL) for the card row action.
    @handouts_by_url = KitchenHandoutLink.pluck(:event_url, :kitchen_handout_id).to_h
    # Latest uploaded grocery receipt per week (keyed by week_start) so each
    # expanded week can show whether a receipt is in / being read.
    @receipt_by_week_start = GroceryReceipt.recent_first.where.not(week_start: nil)
                                           .group_by(&:week_start).transform_values(&:first)
    load_events_data
    # Estimated grocery $ total per week for the orange "Grocery list" card.
    # Read from cache ONLY (never bills Opus on a list render). When a week has
    # recipes but no cached list yet, kick off a background warm so the figure
    # appears on the next load instead of only after someone opens the grocery
    # page.
    svc = grocery_list_service
    @grocery_total_by_week_start = {}
    @weeks.each do |w|
      wr = svc.with_recipe(w[:events])
      next if wr.empty?
      result, cached = svc.fetch(wr, write: false)
      if cached
        @grocery_total_by_week_start[w[:start]] = KitchenAi::GroceryList.total_for(result)
      else
        svc.warm_async(w[:start], w[:end], wr)
      end
    end
    render "admin/kitchen/list", layout: "application"
  end

  # Consolidated shopping list for every class in a date range that has a
  # recipe attached, scaled by how many stations are booked. Defaults to
  # today through the end of the week (the "Wednesday, shop for the weekend"
  # use case); ?days=N widens the window.
  def grocery
    @default_days = default_grocery_days
    # A single class "pull sheet" (event_url from a class row on Sam's list)
    # takes top priority: just that one class's shopping list, printable on
    # demand. Then a specific week (the cart icon); else a forward N-day window.
    if (url = params[:event_url].presence)
      @single_class = true
      @event_url    = url
      @event_name   = params[:name].to_s
      # No date window: load_grocery_data scopes to the one class by URL. A wide
      # range keeps any range-based fallback happy.
      @range = Date.current..(Date.current + 1.year)
    elsif (from = parse_date(params[:from])) && (to = parse_date(params[:to])) && from <= to
      @range = from..to
      @week_mode = true
    else
      @days  = params[:days].presence&.to_i&.clamp(1, 30) || @default_days
      @range = Date.current..(Date.current + @days.days)
    end

    # The aggregation is a slow + paid Opus call, so the heavy work runs in a
    # lazy turbo frame (spinner while it loads) and the result is cached by the
    # recipe set, so a reload or range switch doesn't re-bill Claude.
    return render("admin/kitchen/grocery", layout: "application") unless turbo_frame_request?

    load_grocery_data
    render "admin/kitchen/grocery_list", layout: false
  end

  # Upload a photographed/scanned grocery receipt for a week. We store the
  # image and parse it (Opus vision) in the background into IngredientPrice
  # rows, which future grocery estimates read from. The week is passed as
  # from/to from the list page.
  RECEIPT_MAX_BYTES = 15.megabytes
  def upload_receipt
    file = params[:receipt]
    from = parse_date(params[:from])
    to   = parse_date(params[:to])
    if file.blank?
      return redirect_to(nyk_list_path, alert: "Choose a receipt photo or PDF to upload.")
    end
    if file.size > RECEIPT_MAX_BYTES
      return redirect_to(nyk_list_path, alert: "That file is too large (max 15 MB).")
    end

    receipt = GroceryReceipt.create!(week_start: from, week_end: to, purchased_on: Date.current,
                                     created_by: Current.user, status: "pending")
    receipt.image.attach(file)
    GroceryReceiptExtractionJob.perform_later(receipt.id)
    redirect_to nyk_list_path, notice: "Receipt uploaded. Reading the items now; the prices will save in a minute and sharpen future grocery estimates."
  end

  # The pantry: the latest observed price per ingredient (from receipts), which
  # feeds future grocery estimates. Editable so Lora can fix a misread or drop a
  # junk line (a bottle deposit, a fee).
  def prices
    @prices = IngredientPrice.recent_by_name.values.sort_by(&:canonical_name)
    render "admin/kitchen/prices", layout: "application"
  end

  def update_price
    price = IngredientPrice.find(params[:id])
    attrs = { unit: params[:unit].to_s.strip.presence }
    if params[:unit_price_dollars].present?
      cents = begin
        (Float(params[:unit_price_dollars]) * 100).round
      rescue ArgumentError, TypeError
        nil
      end
      attrs[:unit_price_cents] = cents if cents
    end
    price.update(attrs)
    redirect_to nyk_prices_path, notice: "Updated #{price.canonical_name}."
  end

  def destroy_price
    price = IngredientPrice.find(params[:id])
    price.destroy
    redirect_to nyk_prices_path, notice: "Removed #{price.canonical_name}."
  end

  def test
    load_smoke_data
    render "admin/kitchen/test", layout: "application"
  end

  def data
    load_scrape_data
    render "admin/kitchen/data", layout: "application"
  end

  # Analyst Agent — the sales/revenue dashboard. Reuses the List Agent's data
  # loader (same snapshot rollups); the view renders only the analytical
  # pieces (revenue rollup + trend charts), while List keeps the operational
  # calendar/leaderboards.
  # Admin-only live preview of the weekly Agent Team Report — rendered with the
  # latest snapshot's real data using the exact same builder as the real send
  # (one Carson AI call per load). 404s for everyone else. Not linked in the UI;
  # a shareable internal URL for reviewing the report before it goes out.
  def report_preview
    head :not_found and return unless Current.user&.admin?
    snapshot = KitchenSnapshot.latest
    head :not_found and return unless snapshot
    # Preview skips Carson's AI intro so repeatedly viewing the report doesn't
    # burn Claude tokens; only the real Monday/Friday send pays for it.
    summary = WeeklySalesEmailJob.build_summary(snapshot, carson: false)
    html = KitchenMailer.weekly_sales(summary, recipients: [ "preview@agent44labs.com" ]).html_part.body.to_s
    render html: html.html_safe, layout: false, content_type: "text/html"
  end

  # On-demand team report for NY Kitchen managers (Lora + Rich). Builds the full
  # report (with Carson) from the latest snapshot so a manager can pull a fresh
  # copy any time, e.g. before a board meeting, read/print it, AND get a copy in
  # their inbox. The email goes ONLY to the logged-in user's own address (the
  # sales numbers are sensitive, so we never send to a typed-in address here).
  # Uses the exact builder + template as the scheduled send. Logged as a metered
  # UsageEvent (we record now, decide billing later).
  def generate_report
    snapshot = KitchenSnapshot.latest
    redirect_to(nyk_analyst_path, alert: "No snapshot yet, so there's nothing to report.") and return unless snapshot

    summary = WeeklySalesEmailJob.build_summary(snapshot)
    @emailed_to = Current.user.email_address.presence
    @report_snapshot_date = snapshot.taken_on
    # Render the report HTML for the page (a throwaway mailer instance).
    @report_html = KitchenMailer.weekly_sales(summary, recipients: [ @emailed_to || "preview@agent44labs.com" ]).html_part.body.to_s
    # Email the same content to the logged-in user only (a fresh, untouched
    # instance: deliver_later forbids reading the message before enqueue). No
    # email if they have no address on file. Reuses the one summary above.
    KitchenMailer.weekly_sales(summary, recipients: [ @emailed_to ]).deliver_later if @emailed_to

    UsageEvent.record!(workspace: @nyk_workspace, user: Current.user,
                       kind: "report.on_demand",
                       metadata: { snapshot: snapshot.taken_on.to_s, emailed_to: @emailed_to })
    render "kitchen/generate_report", layout: "application"
  end

  def analyst
    @sendable_workspaces = sendable_workspaces_for(Current.user) # for "Needs a push" → Social Agent
    load_events_data
    agent = @workspace_agents["analyst"]
    subs  = Array(agent&.setting(:weekly_email_subscriber_ids)).map(&:to_i)
    @analyst_subscribed = Current.user && subs.include?(Current.user.id)

    # Admin-only: who actually opened the dashboard after the last report send
    # (reliable engagement signal vs an Outlook-spoofed open pixel).
    @report_engagement = WeeklySalesEmailJob.recipient_engagement if Current.user&.admin?

    # Time-range scoreboard. Forward windows scope the revenue rollup + the
    # "upcoming" leaderboards over future classes (sold vs left to sell).
    # Retrospective windows ("last …") scope over PAST classes and report what
    # was booked vs missed. The trend charts + "All time" leaderboard stay
    # unscoped.
    today      = Date.current
    week_start = today.beginning_of_week(:monday) # Mon→Sun weeks (Lora's preference)
    week_end   = today.end_of_week(:monday)       # this week's Sunday

    forward = {
      "week"     => { label: "Current week", to: week_end },
      "nextweek" => { label: "Next week",    from: week_end + 1, to: week_end + 7 }, # the discrete next week, like the List bucket
      "month"    => { label: "This month",   to: today.end_of_month },
      "all"      => { label: "All upcoming", to: nil }
    }
    back = {
      "lastweek"    => { label: "Last week",    from: week_start - 7,                                        to: week_start - 1 },
      "lastmonth"   => { label: "Last month",   from: today.last_month.beginning_of_month,                   to: today.last_month.end_of_month },
      "lastquarter" => { label: "Last quarter", from: (today.beginning_of_quarter - 1).beginning_of_quarter, to: today.beginning_of_quarter - 1 },
      "lastyear"    => { label: "Last year",    from: today.last_year.beginning_of_year,                     to: today.last_year.end_of_year }
    }

    # Day-level ranges: tickets actually booked on a single day (observed-sales
    # basis, same as the momentum cards), not capacity-based revenue like the
    # week/month ranges. They sit between "Last week" and "Current week".
    daily = {
      "yesterday" => { label: "Yesterday", date: today - 1 },
      "today"     => { label: "Today",     date: today }
    }

    # Only offer a retrospective range once it has data (we have ~6 weeks of
    # history, so quarter/year stay hidden until they fill in).
    avail_back = back.select { |_k, w| KitchenSnapshot.any_classes_between?(w[:from], w[:to]) }

    @range = params[:range].to_s
    unless forward.key?(@range) || avail_back.key?(@range) || daily.key?(@range)
      @range = "week" # default: current week
    end
    @retrospective = back.key?(@range)
    @daily_view    = daily.key?(@range)

    # Buttons left→right: oldest retrospective → Yesterday/Today → upcoming.
    @range_options = avail_back.keys.reverse.map { |k| [ k, back[k][:label] ] } +
                     daily.keys.map { |k| [ k, daily[k][:label] ] } +
                     forward.keys.map { |k| [ k, forward[k][:label] ] }

    if @daily_view
      d = daily[@range]
      @range_label = d[:label]
      @day_date    = d[:date]
      @day_booking = KitchenSnapshot.bookings_daily_total(d[:date], d[:date])
      priced = [] # day ranges use the booking total, not the capacity rollup
    elsif @retrospective
      w = back[@range]
      @range_label = w[:label]
      priced = KitchenSnapshot.classes_ended_between(w[:from], w[:to]).select(&:capacity_known?)
    else
      w = forward[@range]
      @range_label = w[:label]
      @range_end   = w[:to]
      from         = w[:from]
      in_window = ->(e) {
        d = e&.start_at&.to_date
        d && (from.nil? || d >= from) && (@range_end.nil? || d <= @range_end)
      }
      priced = Array(@events).select { |e| in_window.call(e) && e.capacity_known? }
    end

    @rev_priced_count = priced.size
    @rev_proxy_count  = priced.count(&:capacity_via_proxy?)
    @rev_sold  = priced.sum(&:revenue_sold)
    @rev_total = priced.sum(&:revenue_total)
    @rev_left  = @rev_total - @rev_sold
    # Revenue-based ($sold / $total) to match the bar above and the List page +
    # weekly email "% of $ sold", rather than seats-sold / seats-total.
    @rev_pct_sold = @rev_total.to_f.positive? ? (100.0 * @rev_sold / @rev_total).round : nil

    # Recent booking momentum — tickets actually sold yesterday and today,
    # independent of the selected range. Same observed-sales basis as the weekly
    # chart (bookings_daily_total), so it reconciles with "Booked this week".
    @today_bookings     = KitchenSnapshot.bookings_daily_total(today, today)
    @yesterday_bookings = KitchenSnapshot.bookings_daily_total(today - 1, today - 1)

    # Pace/at-risk leaderboards make no sense for a past window or a single day
    # — forward only. (Overrides the unscoped values load_events_data set.)
    # Day ranges also never define in_window, so this guard avoids a NameError.
    @top_sellers = @needs_a_push = []
    if !@retrospective && !@daily_view && (snap = KitchenSnapshot.latest)
      @top_sellers  = KitchenSnapshot.selling_fastest(snapshot: snap, limit: 40).select { |r| in_window.call(r[:event]) }.first(5)
      @needs_a_push = KitchenSnapshot.needs_a_push(snapshot: snap, limit: 40).select { |r| in_window.call(r[:event]) }.first(5)
    end

    render "admin/kitchen/analyst", layout: "application"
  end

  # Toggle the current user's opt-in to the Friday weekly sales recap. Stores
  # subscriber user IDs on the Analyst agent; the job resolves them to emails
  # at send time (so an email change carries over automatically).
  def update_analyst_subscription
    workspace = Workspace.find_by(slug: "nykitchen")
    user = Current.user
    return redirect_to(nyk_analyst_path, alert: "Sign in to subscribe.") unless workspace && user
    if user.email_address.blank?
      return redirect_to nyk_analyst_path, alert: "Add an email to your profile first, then subscribe."
    end
    agent = workspace.agent_for("analyst")
    ids = Array(agent.setting(:weekly_email_subscriber_ids)).map(&:to_i)
    now_subscribed = !ids.include?(user.id)
    ids = now_subscribed ? (ids + [ user.id ]) : (ids - [ user.id ])
    agent.update_settings(weekly_email_subscriber_ids: ids.uniq)
    redirect_to nyk_analyst_path,
      notice: now_subscribed ? "Subscribed — you'll get the Friday sales recap at #{user.email_address}." : "Unsubscribed from the weekly recap."
  end

  # Super Agent — chat surface for read-only Q&A about NYK classes. The view
  # holds the conversation in-browser; each turn POSTs the full history to
  # #ask_message, which calls KitchenAi::AskAgent.
  def ask
    snapshot = KitchenSnapshot.latest
    @last_snapshot_taken_on = snapshot&.taken_on
    ask_agent = @nyk_workspace&.agent_for("ask")
    custom = Array(ask_agent&.setting(:chip_prompts)).compact_blank
    @chip_prompts = custom.any? ? custom.first(4) : dynamic_chip_prompts(snapshot)
    @can_edit_chips = %w[owner admin].include?(@my_workspace_role)
    @super_agent_usage = super_agent_usage_windows if Current.user&.admin?
    render "admin/kitchen/ask", layout: "application"
  end

  def update_ask_examples
    workspace = Workspace.find_by(slug: "nykitchen")
    unless workspace && %w[owner admin].include?(workspace.role_for(Current.user))
      redirect_to nyk_ask_path, alert: "Only workspace admins can edit examples." and return
    end
    prompts = params[:chip_prompts].to_s
                .split(/\r?\n/).map(&:strip).reject(&:blank?).first(4)
    workspace.agent_for("ask").update_settings(chip_prompts: prompts)
    redirect_to nyk_ask_path, notice: "Examples saved."
  end

  def ask_message
    return render(json: { error: "sign_in_required" }, status: :unauthorized) unless Current.user
    return render(json: { error: "not_authorized" }, status: :forbidden) unless nyk_super_agent_allowed?

    messages = params[:messages]
    messages = messages.is_a?(Array) ? messages.map { |m| m.to_unsafe_h.symbolize_keys } : []

    # Dogfood rollout: admins get the read-only agentic agent (tools, loop);
    # everyone else stays on the stable single-shot AskAgent. Action tools stay
    # off (enable_writes); the low-risk config tools (save developer email) are
    # on so admins can set it from chat.
    result =
      if Current.user.admin?
        KitchenAi::AgenticAgent.new(user: Current.user, enable_config: true).run(messages)
      else
        KitchenAi::AskAgent.new(user: Current.user).ask(messages)
      end

    if result.ok?
      render json: { reply: result.reply }
    else
      render json: { error: result.error }, status: 502
    end
  end

  # Allow the Display Agent settings page to preview the live monitor
  # output in an iframe. The default app-wide CSP sets frame-ancestors 'none'.
  content_security_policy(only: :display) do |policy|
    policy.frame_ancestors :self
  end

  # Public, no-auth screen for the tasting-room display monitor.
  # Cycles through currently-available classes; the page meta-refreshes
  # periodically. Honors the Display Agent's settings on the NYK workspace.
  # When visibility is "private", requires a matching ?token=… param.
  def display
    @agent = nyk_display_agent
    if @agent.setting(:visibility) == "private" &&
       params[:token].to_s != @agent.setting(:share_token).to_s
      head :not_found and return
    end
    snapshot = KitchenSnapshot.latest
    available = snapshot ? snapshot.kitchen_events.upcoming.reject(&:sold_out?) : []
    @events = available.first(@agent.setting(:slide_count).to_i)
    @available_total = available.size
    @last_updated = snapshot&.taken_on
    @display_workspace = Workspace.find_by(slug: "nykitchen")
    render "admin/kitchen/display", layout: false
  end

  # Display Agent settings: configuration form + share URL + preview.
  def display_settings
    @agent = nyk_display_agent
    @workspace = Workspace.find_by(slug: "nykitchen")
    @my_workspace_role = @workspace&.role_for(Current.user)
    @workspace_agents = WorkspaceAgent::KINDS.index_with { |k| @workspace&.agent_for(k) }
    render "admin/kitchen/display_settings", layout: "application"
  end

  def update_display_settings
    workspace = Workspace.find_by(slug: "nykitchen")
    unless workspace && %w[owner admin].include?(workspace.role_for(Current.user))
      redirect_to nyk_display_settings_path, alert: "Only workspace admins can change Display settings." and return
    end
    agent = workspace.agent_for("display")
    permitted = params.require(:settings).permit(
      :visibility, :slide_count, :advance_seconds, :refresh_minutes,
      :show_price, :show_spots, :show_end_time, :show_image, :show_qr
    ).to_h
    permitted["visibility"] = "public" unless %w[public private].include?(permitted["visibility"])
    %w[show_price show_spots show_end_time show_image show_qr].each do |k|
      permitted[k] = ActiveModel::Type::Boolean.new.cast(permitted[k]) if permitted.key?(k)
    end
    %w[slide_count advance_seconds refresh_minutes].each do |k|
      permitted[k] = permitted[k].to_i if permitted.key?(k)
    end
    agent.update_settings(permitted)
    # First-time toggle to private without a token: generate one now.
    agent.share_token_or_generate! if permitted["visibility"] == "private"
    redirect_to nyk_display_settings_path, notice: "Display settings saved."
  end

  # Printable handouts of the next N non-sold-out classes. Two layouts (Lora's
  # request), both fed by the same upcoming-classes data:
  #   flyer (default) — grab-and-go front-desk handout, 18 classes laid out 9
  #                     to a side so it prints double-sided on one sheet; photos
  #                     + QR per row.
  #   stall           — big-font poster for the bathroom stalls, 6 classes on
  #                     one side, no photos, large QR to scan up close.
  # Counts are fixed defaults but overridable ad-hoc with ?n=. Independent of
  # the TV's slide_count, which only limits the rotating on-screen carousel.
  def display_print
    @agent = nyk_display_agent
    snapshot = KitchenSnapshot.latest
    @variant = params[:variant] == "stall" ? "stall" : "flyer"
    @per_page = 9 # flyer: forces a clean 9-front / 9-back page break
    default_limit = @variant == "stall" ? 6 : 18
    @print_limit = params[:n].present? ? params[:n].to_i.clamp(1, 60) : default_limit
    upcoming = snapshot ? snapshot.kitchen_events.upcoming.reject(&:sold_out?) : []
    @events = upcoming.first(@print_limit)
    @more_count = upcoming.size - @events.size
    @last_updated = snapshot&.taken_on
    # Photos default on for both layouts; ?photos=0 prints a leaner text-only run.
    @show_photos = params[:photos].to_s != "0"
    # Count flyer/poster prints (admin-only readout on the Neon hub card). Bump
    # per print-page open; tracked per variant + a combined total.
    Setting.increment("nyk_flyer_prints:total")
    Setting.increment("nyk_flyer_prints:#{@variant}")
    Setting.touch_time("nyk_flyer_prints:last_at") # CarsonNudgeJob no_flyers trigger
    template = @variant == "stall" ? "admin/kitchen/display_print_stall" : "admin/kitchen/display_print"
    render template, layout: false
  end

  def rotate_display_token
    workspace = Workspace.find_by(slug: "nykitchen")
    unless workspace && %w[owner admin].include?(workspace.role_for(Current.user))
      redirect_to nyk_display_settings_path, alert: "Only workspace admins can rotate the token." and return
    end
    workspace.agent_for("display").rotate_share_token!
    redirect_to nyk_display_settings_path, notice: "Share link regenerated. The old link no longer works."
  end

  # Liveness ping from the live display screen (fires ~every 60s from the
  # page JS). We record last-seen ONLY when the posted token matches the
  # Display Agent's private share_token, so the hub dot reflects the real
  # kitchen screen being on — not a random visitor to a public URL. A blank
  # or wrong token is silently ignored (still 204) so nothing leaks.
  def display_heartbeat
    token = nyk_display_agent.setting(:share_token).to_s
    if token.present? && ActiveSupport::SecurityUtils.secure_compare(params[:token].to_s, token)
      Setting.touch_time("nyk_display:last_seen_at")
      DisplayHeartbeat.record! # per-day presence for Neon's weekly uptime brief
    end
    head :no_content
  end


  # PATCH /nykitchen/agents/:kind  — workspace owner/admin renames an
  # agent (sets WorkspaceAgent#display_name). Pass display_name="" to
  # clear. Anyone else gets a redirect with an alert.
  def rename_agent
    kind = params[:kind].to_s
    unless WorkspaceAgent::KINDS.include?(kind)
      redirect_to nykitchen_path, alert: "Unknown agent." and return
    end
    workspace = Workspace.find_by(slug: "nykitchen")
    role = workspace&.role_for(Current.user)
    unless workspace && %w[owner admin].include?(role)
      redirect_to nykitchen_path, alert: "Only workspace admins can rename agents." and return
    end
    agent = workspace.agent_for(kind)
    name = params[:display_name].to_s.strip
    if agent.update(display_name: name.presence)
      label = agent.display_name.presence || "##{agent.agent_number}"
      redirect_back fallback_location: nykitchen_path, notice: "Renamed to #{label}."
    else
      redirect_back fallback_location: nykitchen_path, alert: agent.errors.full_messages.first || "Couldn't rename."
    end
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

  # Email a failed smoke run's report to any address a manager enters, e.g. an
  # outside developer. Bundles the error/console/steps with signed artifact
  # links (mailer). Logged as a metered UsageEvent. Manager-gated.
  def send_smoke_report
    run = SmokeTestRun.find(params[:id])
    email = params[:email].to_s.strip
    unless email.match?(URI::MailTo::EMAIL_REGEXP)
      redirect_to(nyk_test_path(status: "failed"), alert: "Enter a valid email address.") and return
    end

    KitchenMailer.smoke_failure_report(run, recipient: email,
      note: params[:note], from_name: Current.user&.email_address).deliver_later
    UsageEvent.record!(workspace: @nyk_workspace, user: Current.user,
                       kind: "test_report.send",
                       metadata: { to: email, smoke_run_id: run.id, name: run.name })
    redirect_to nyk_test_path(status: "failed"), notice: "Failure report sent to #{email}."
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

  # Empty-state chip suggestions for Super Agent. When workspace admins
  # haven't pinned their own, build 4 that reference real upcoming classes
  # from the latest snapshot — proves Super Agent talks about the actual
  # calendar, not generic Q&A.
  def dynamic_chip_prompts(snapshot)
    fallback = [
      "What classes sold out this week?",
      "Which are almost sold out?",
      "What's selling fastest right now?",
      "How are weekend classes doing vs weekdays?"
    ]
    return fallback unless snapshot

    upcoming = snapshot.kitchen_events.upcoming.to_a
    return fallback if upcoming.empty?

    chips = []

    almost = upcoming.select { |e| !e.sold_out? && e.spots_left.present? && e.spots_left.between?(1, 5) }
    if (pick = almost.sample)
      chips << "How is the #{chip_class_label(pick)} class selling?"
    end

    if (pick = upcoming.select(&:sold_out?).sample)
      chips << "Why did #{chip_class_label(pick)} sell out?"
    end

    chips << "What sold out this week?"
    chips << "How are weekend classes doing vs weekdays?"

    chips.uniq.first(4)
  end

  # Trim trailing date suffixes like " 5/23/26" or "Class 5/23" so the
  # chip reads naturally instead of repeating the date.
  def chip_class_label(event)
    name = event.name.to_s
    name = name.sub(/\s*[-–—:]?\s*Class\s*\d{1,2}\/\d{1,2}(\/\d{2,4})?\s*$/i, "")
    name = name.sub(/\s*\(?\d{1,2}\/\d{1,2}(\/\d{2,4})?\)?\s*$/, "")
    name.truncate(40)
  end

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
        .sort_by { |ws| [ ws.slug.include?("kitchen") ? 0 : 1, ws.name.to_s.downcase ] }
  end

  # Daily Super Agent "morning question" on the hub card, shown only to the
  # trial user named in the kv setting `super_agent_daily_prompt_email`. Set
  # that setting to roll the trial from RB → Lora (→ a list) with no deploy;
  # blank it to turn the feature off. Returns the question string or nil.
  def morning_prompt_for(user)
    return nil unless daily_prompt_trial?(user)
    KitchenAi::MorningPrompt.question
  end

  # True when `user` is the trial recipient named in super_agent_daily_prompt_email.
  def daily_prompt_trial?(user)
    return false unless user
    trial = Setting.get("super_agent_daily_prompt_email").to_s.strip.downcase
    trial.present? && user.email_address.to_s.strip.downcase == trial
  end

  # When the calendar smoke test has failed several runs in a row, the trial
  # user's Super Agent card is promoted to an alert offering to draft a note to
  # the developer. Takes priority over the morning question. Returns
  # { count:, prompt: } or nil.
  def smoke_alert_for(user)
    return nil unless daily_prompt_trial?(user)
    n = KitchenAi::SmokeEscalation.streak
    return nil unless KitchenAi::SmokeEscalation.alerting?(n)
    { count: n, prompt: KitchenAi::SmokeEscalation.draft_prompt(n) }
  end

  # Admin-only readout of Super Agent (chat) token usage + cost across a few
  # time windows, so the team can watch spend as Lora uses it. Covers both the
  # AskAgent (nyk_ask) and AgenticAgent (nyk_agent) sources.
  def super_agent_usage_windows
    base = AiCallLog.super_agent
    now  = Time.zone.now
    {
      today:    AiCallLog.usage_rollup(base.where("created_at >= ?", now.beginning_of_day)),
      week:     AiCallLog.usage_rollup(base.where("created_at >= ?", 7.days.ago)),
      month:    AiCallLog.usage_rollup(base.where("created_at >= ?", now.beginning_of_month)),
      all_time: AiCallLog.usage_rollup(base)
    }
  end

  # Per-agent "salary" for the NYK hub: this month's token usage + dollar cost,
  # mapped from AI sources / smoke runs to each agent card. A good rollup, not
  # forensic — usage is logged by feature source, not agent id. Sam (list) and
  # Neon (display) draw no paid usage, so they read $0. Owner/admin only.
  def hub_salary_by_agent
    month = Time.zone.now.beginning_of_month
    ai = ->(sources) {
      r = AiCallLog.where(source: sources).where("created_at >= ?", month).usage_rollup
      { tokens: r[:total_tokens], cost: r[:cost_dollars] }
    }
    smoke = ->(scope) {
      { tokens: 0, cost: SmokeTestRun.public_send(scope).where("started_at >= ?", month).sum(:cost_dollars).to_f }
    }
    {
      "ask"     => ai.call(AiCallLog::SUPER_AGENT_SOURCES),
      "social"  => ai.call(%w[nyk_enhance nyk_x_autopost]),
      "analyst" => ai.call(%w[nyk_team_report]),
      "test"    => smoke.call(:nyk_nav),
      "data"    => smoke.call(:nyk_scrape),
      "list"    => { tokens: 0, cost: 0.0 },
      "display" => { tokens: 0, cost: 0.0 }
    }
  end

  # Who's allowed to use the Super Agent (admin chat loop or single-shot ask).
  # Admins + the App Store reviewer + any member of the NYK workspace (Lora's
  # team). Other signed-in users get :not_found / :forbidden — they shouldn't
  # be able to spend our Claude credits just by creating an account.
  def nyk_super_agent_allowed?
    user = Current.user
    return false unless user
    return true if user.admin? || user.reviewer?
    (@nyk_workspace || Workspace.find_by(slug: "nykitchen"))&.member?(user) || false
  end

  def require_nyk_super_agent_access
    head :not_found unless nyk_super_agent_allowed?
  end

  # Gate + load for the on-demand report actions: only NY Kitchen managers
  # (owner/admin = Lora + Rich) may generate or send the report. 404 otherwise.
  def require_nyk_manager
    @nyk_workspace ||= Workspace.find_by(slug: "nykitchen")
    head :not_found unless @nyk_workspace&.manager?(Current.user)
  end

  def parse_date(str)
    Date.parse(str.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # Today through the end of this week (Sunday). Min 3 days so a Friday/Saturday
  # still gives a usable weekend window.
  def default_grocery_days
    [ (7 - Date.current.cwday) % 7, 3 ].max
  end

  # The grocery list service for this request (memoizes the handouts map +
  # observed prices so the list page can total every week cheaply). Shared with
  # GroceryListWarmJob so they hit the same cache key.
  def grocery_list_service
    @grocery_list_service ||= KitchenAi::GroceryList.new(user: Current.user)
  end

  # Gather the in-range classes, split into with/without recipe, assign each a
  # short colored tag, and run (or fetch from cache) the aggregated list.
  def load_grocery_data
    snapshot = KitchenSnapshot.latest
    svc = grocery_list_service
    # Include SOLD-OUT classes: those are the fullest ones, exactly what you
    # need to shop for (unlike the promo flyer, which hides sold-out classes).
    # A pull sheet (@single_class) scopes to one class by URL; otherwise the
    # whole date window.
    events = if snapshot
      scope = snapshot.kitchen_events.upcoming
      scope = if @single_class
        scope.select { |e| e.url == @event_url }
      else
        scope.select { |e| @range.cover?(e.start_at.to_date) }
      end
      scope.sort_by(&:start_at)
    else
      []
    end

    @with_recipe    = svc.with_recipe(events)
    @without_recipe = events.reject { |e| svc.handouts_by_event_url[e.url] }

    @total_headcount = @with_recipe.sum { |c| c[:headcount].to_i }
    # Index per tag -> the view maps it to a (Tailwind-scannable) chip color.
    @tag_index = {}
    @with_recipe.each_with_index { |c, i| @tag_index[c[:tag]] = i }
    # Per-tag recipe lines for the hover/tap popover (full recipe amounts).
    @recipe_by_tag = @with_recipe.to_h do |c|
      lines = c[:handout].recipes.flat_map do |r|
        Array(r["ingredients"]).map { |i| [ i["qty"], i["item"] ].map(&:to_s).reject(&:blank?).join(" ") }
      end.reject(&:blank?)
      [ c[:tag], lines ]
    end
    return if @with_recipe.empty?

    @result, @from_cache = svc.fetch(@with_recipe)
  end

  def set_common_view_state
    @admin = authenticated? && (Current.user.admin? || Current.user.reviewer?)
    @can_see_pricing = Workspace.find_by(slug: "nykitchen")&.pricing_visible_for?(Current.user) || false
    # The NYK workspace itself (slug 'nykitchen'). All four agent pages
    # need it so the WorkspaceAgent badge + pet-name can render in the
    # title row. Anonymous viewers (hub only) get nil.
    @nyk_workspace ||= Workspace.find_by(slug: "nykitchen")
    @workspace_agents = @nyk_workspace ? WorkspaceAgent::KINDS.index_with { |k| @nyk_workspace.agent_for(k) } : {}
    @my_workspace_role = @nyk_workspace && Current.user ? @nyk_workspace.role_for(Current.user) : nil
  end

  # Hub cards self-organize: the agents you open most rise to the top.
  # The default order doubles as the layout for anonymous viewers and the
  # tie-break, so rarely-used cards never shuffle among themselves.
  HUB_CARD_DEFAULT_ORDER = %w[analyst list social display data test cellar ask].freeze

  # Ranking signal: visits to the page each card opens (already in PageView,
  # per user) — no separate click tracking needed.
  HUB_CARD_PATHS = {
    "analyst" => "/nykitchen/analyst",
    "list"    => "/nykitchen/list",
    "social"  => "/nykitchen/social",
    "display" => "/nykitchen/display/settings",
    "data"    => "/nykitchen/data",
    "test"    => "/nykitchen/test",
    "cellar"  => "/nykitchen/inventory",
    "ask"     => "/nykitchen/ask"
  }.freeze

  # kind => CSS order index. Agents flagging a problem (red dot) jump the
  # queue regardless of usage, so a dead marquee can't hide at the bottom
  # just because it's rarely opened. Pinning is live (never cached) — a
  # failure must surface immediately.
  def hub_card_order
    order = hub_card_frequency_order
    failed = (@hub_agent_status || {}).filter_map { |kind, s| kind.to_s if s == :failed }
    pinned = order.select { |k| failed.include?(k) }
    (pinned + (order - pinned)).each_with_index.to_h
  end

  # Frequency ranking from the last 30 days of the user's page views,
  # cached for the rest of the day so cards don't reshuffle mid-session.
  def hub_card_frequency_order
    return HUB_CARD_DEFAULT_ORDER unless Current.user

    Rails.cache.fetch("nyk_hub_card_order:v1:#{Current.user.id}:#{Date.current}", expires_in: 1.day) do
      counts = PageView.where(user_id: Current.user.id, path: HUB_CARD_PATHS.values)
                       .where("created_at >= ?", 30.days.ago)
                       .group(:path).count
      HUB_CARD_DEFAULT_ORDER.sort_by.with_index { |kind, i| [ -counts.fetch(HUB_CARD_PATHS[kind], 0), i ] }
    end
  end

  # The user's NYK-flavored workspace, if any — backs the Social Agent card
  # on the hub. Falls back to nil; the card then links to /workspaces.
  def nyk_display_agent
    Workspace.find_by(slug: "nykitchen")&.agent_for("display") ||
      WorkspaceAgent.new(kind: "display", settings: {})
  end

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
    # Sales revenue (ticket $) is the kitchen's own data — show it to the
    # workspace's managers (owner/admin role) + app admins. Plain members /
    # kitchen_customers still see seats, not dollars. Distinct from
    # @can_see_pricing, which gates OUR internal agent/compute costs.
    ws_role = (@nyk_workspace || Workspace.find_by(slug: "nykitchen"))&.role_for(Current.user)
    @show_revenue = Current.user&.admin? || %w[owner admin].include?(ws_role.to_s)
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
        @weeks << { label: label, events: week_events, expanded: @weeks.size < 2,
                    start: week_start, end: week_end }
        week_start = week_end + 1
        week_end = week_start + 6
      end

      @total = @events.size
      @sold_out = @events.count(&:sold_out?)
      @last_updated = snapshot.taken_on

      # Revenue rollup (face value: list price × seats), across classes whose
      # capacity is known. Mirrors the per-week math in _list_panel; biased low
      # for proxy-capacity classes (see KitchenEvent#revenue_*).
      priced_events     = @events.select(&:capacity_known?)
      @rev_priced_count = priced_events.size
      @rev_proxy_count  = priced_events.count(&:capacity_via_proxy?)
      @rev_sold         = priced_events.sum(&:revenue_sold)
      @rev_total        = priced_events.sum(&:revenue_total)
      @rev_left         = @rev_total - @rev_sold

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

      # Day-of-week ticket sales: 6-week historical avg vs this week's actuals.
      @dow_avg       = KitchenSnapshot.tickets_sold_by_wday
      @dow_this_week = KitchenSnapshot.tickets_sold_this_week_by_wday

      # Tickets sold per week / month since tracking began — sales trend.
      @weekly_sales  = KitchenSnapshot.tickets_sold_by_week
      @monthly_sales = KitchenSnapshot.tickets_sold_by_month

      # "Selling fastest" card — ranked by observed pace. Two views toggled
      # client-side: upcoming-only (default) and all-time (past + future).
      @top_sellers     = KitchenSnapshot.selling_fastest(snapshot: snapshot)
      @top_sellers_all = KitchenSnapshot.selling_fastest(snapshot: snapshot, scope: :all, window_weeks: nil)

      # "Needs a push" card: upcoming classes behind pace (default) + an
      # all-time retrospective of past classes that ended with unsold seats.
      @needs_a_push    = KitchenSnapshot.needs_a_push(snapshot: snapshot)
      @ended_emptiest  = KitchenSnapshot.ended_emptiest(snapshot: snapshot)
    else
      @events = []
      @weeks = []
      @total = 0
      @sold_out = 0
      @top_sellers = []
      @top_sellers_all = []
      @needs_a_push = []
      @ended_emptiest = []
      @workspace_status_by_url = {}
      @filter_counts = { "all" => 0, "instock" => 0, "limited" => 0, "soldout" => 0, "closed" => 0, "other" => 0 }
      @post_logs = {}
      @rev_priced_count = 0
      @rev_proxy_count  = 0
      @rev_sold = @rev_total = @rev_left = 0
      @weekly_sales = []
      @monthly_sales = []
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

    # Exclude in-flight ("running") rows from the table — they're transient
    # and will land as passed/failed when the run finishes.
    windowed_scope = nav_scope.finished.where("started_at >= ?", @smoke_days.days.ago)
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
    # Genuine sellouts among upcoming classes ("SoldOut", not the "Closed" sales
    # cutoff) → the "sold-out percentage" Sam's card advertises. SQL counts, no
    # event load. Iris owns revenue %; Sam owns availability.
    @hub_events_sold_out = snapshot ? snapshot.kitchen_events.upcoming.where("LOWER(availability) LIKE ?", "%soldout%").count : 0
    @hub_events_sold_out_pct = @hub_events_total.positive? ? (100.0 * @hub_events_sold_out / @hub_events_total).round : nil
    # Tickets sold since yesterday's snapshot. Only meaningful when the
    # latest snapshot was taken today — otherwise it'd be reporting a
    # delta from two days ago, not "today".
    @hub_tickets_sold_today = (snapshot&.taken_on == Date.current) ? snapshot.tickets_sold_today : nil

    # Linear pace vs daily average, within an 8am–8pm operating window.
    # `expected_by_now` is what we'd expect to have sold by this hour if
    # sales tracked the daily average linearly across the window. Before
    # 8am there's nothing to compare against.
    @hub_tickets_sold_avg = KitchenSnapshot.tickets_sold_daily_avg
    if @hub_tickets_sold_today && @hub_tickets_sold_avg
      now = Time.current
      hour_frac = (now.hour + now.min / 60.0 - 8.0) / 12.0
      hour_frac = hour_frac.clamp(0.0, 1.0)
      expected_by_now = @hub_tickets_sold_avg * hour_frac
      @hub_tickets_expected_by_now = expected_by_now.round(1)
      @hub_tickets_pace_pct = expected_by_now.positive? ?
        ((@hub_tickets_sold_today / expected_by_now - 1) * 100).round : nil
    end

    nav    = SmokeTestRun.nyk_nav
    scrape = SmokeTestRun.nyk_scrape

    # Most-recent row (incl. running rows) for presence-dot logic.
    @hub_smoke_last       = nav.recent.first
    # Most-recent FINISHED row for the headline "Passed N ago" line — we
    # don't want a momentary in-flight row to wipe out the last result.
    @hub_smoke_last_finished = nav.finished.recent.with_attached_video.with_attached_thumbnail.first
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
    # Scout's work product: calendar changes it detected this week (added /
    # removed / price changes). Same builder the weekly report uses; this is
    # what "powers ticket-change alerts" means. "This week" = Mon–Sun (Lora's
    # convention, matches the analyst page), so the count resets each Monday.
    @hub_scrape_churn = KitchenSnapshot.calendar_churn(Date.current.beginning_of_week(:monday))
    @hub_scrape_changes = @hub_scrape_churn.values.sum

    # Neon flyer/poster print count — admin-only readout on the Display card.
    @hub_flyer_prints = Setting.counter("nyk_flyer_prints:total") if Current.user&.admin?

    # Echo's last published post (any connected account) — shows the card is
    # actually broadcasting. nil when nothing's been posted yet.
    @hub_last_post = @nyk_workspace&.workspace_posts&.posted&.order(posted_at: :desc)&.first

    # Iris mini "sales by day of week" sparkline — 6-week avg per weekday
    # (Sun..Sat). Tiny CSS bars on the hub card; full chart lives on /analyst.
    @hub_dow_avg = KitchenSnapshot.tickets_sold_by_wday

    @hub_display_last_seen = Setting.time("nyk_display:last_seen_at")
    @hub_agent_status = {
      list:    list_agent_status,
      test:    test_agent_status,
      data:    data_agent_status,
      social:  social_agent_status,
      display: display_agent_status
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
  DISPLAY_CADENCE = 3.minutes # screen pings every 60s; allow 2 missed beats
  # Past this, a "running" row is treated as orphaned (the client crashed
  # before PATCHing the result back) so the dot stops pulsing.
  RUNNING_MAX_AGE = 15.minutes

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

  # Display presence is a heartbeat, not a scheduled run. Only meaningful in
  # private mode — that's the gate the user chose: a green dot requires the
  # tokenized screen URL to be pinging. Returns nil in public mode so the hub
  # omits the dot entirely (we have no honest signal there). :running while a
  # beat landed within DISPLAY_CADENCE (pulsing green = carousel live at NYK);
  # :failed (red) once the screen goes dark — so Lora, viewing from home,
  # sees red the moment the carousel stops playing on the NY Kitchen screen.
  def display_agent_status
    return nil unless nyk_display_agent.setting(:visibility) == "private"
    return :failed unless @hub_display_last_seen
    Time.current - @hub_display_last_seen < DISPLAY_CADENCE ? :running : :failed
  end

  # Smoke/scrape presence: a SmokeTestRun row exists for each kickoff.
  # - last_run: most recent row (may be status=running, i.e. in flight)
  # - last_finished: most recent passed/failed row, ignoring running ones
  # - cadence: how recently a finished run must have landed to count as
  #   "on cadence" (i.e. healthy enough to be solid green)
  def agent_status_from_runs(last_run, last_finished, cadence)
    return :stale  unless last_run || last_finished
    if last_run&.running? && Time.current - last_run.started_at < RUNNING_MAX_AGE
      return :running
    end
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
