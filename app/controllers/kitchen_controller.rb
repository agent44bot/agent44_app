class KitchenController < ApplicationController
  allow_unauthenticated_access

  def index
    @admin = authenticated? && (Current.session.user.admin? || Current.session.user.reviewer?)
    @can_see_pricing = authenticated? && (Current.session.user.admin? || Current.session.user.kitchen_only?)
    load_kitchen_data
    render "admin/kitchen/index", layout: "application"
  end

  def digest
    @digest = KitchenTicketDigest.find(params[:id])
    @snapshot = @digest.kitchen_snapshot
    @can_see_pricing = authenticated? && (Current.session.user.admin? || Current.session.user.kitchen_only?)
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
    api_key = ENV["ANTHROPIC_API_KEY"]
    if api_key.blank?
      render json: { error: "no_api_key", message: "API key not configured" }, status: 422
      return
    end

    client = Anthropic::Client.new(api_key: api_key)
    prompt = build_enhance_prompt(params[:draft], params[:event_name], params[:event_description], params[:event_date], params[:event_price])

    response = client.messages.create(
      model: "claude-haiku-4-5-20251001",
      max_tokens: 600,
      messages: [ { role: "user", content: prompt } ]
    )

    enhanced = response.content.first.text

    log = SocialPostLog.find_or_initialize_by(event_url: params[:event_url])
    log.enhanced_text = enhanced
    log.save!

    Current.session&.user&.increment!(:ai_enhances_used)

    render json: { enhanced: enhanced }
  rescue Anthropic::Errors::APIError => e
    render json: { error: "api_error", message: e.message }, status: 502
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

  def load_kitchen_data
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
    else
      @events = []
      @weeks = []
      @total = 0
      @sold_out = 0
      @filter_counts = { "all" => 0, "instock" => 0, "limited" => 0, "soldout" => 0, "closed" => 0, "other" => 0 }
      @post_logs = {}
    end

    @smoke_runs = SmokeTestRun.for_name("nyk_calendar_nav").recent.with_attached_video.with_attached_thumbnail.limit(20)
  end

  def build_enhance_prompt(draft, name, description, date, price)
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
