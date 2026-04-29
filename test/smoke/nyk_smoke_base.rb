require "test_helper"
require "fileutils"
require "playwright"
require "net/http"
require "json"
require "socket"
require_relative "nyk_event_scraper_helper"

# Shared harness for NY Kitchen smoke tests. Subclasses define a `test` method
# and the constants TEST_NAME and ARTIFACT_PREFIX. Everything else — Playwright
# harness, Vlad status, console listeners, smoke-run/snapshot POSTs, failure
# email, video upload — is inherited from here.
class NykSmokeBase < ActiveSupport::TestCase
  include NykEventScraperHelper

  TARGET_URL    = NykSmokeMailer::TARGET_URL
  ARTIFACT_DIR  = Rails.root.join("tmp", "smoke")
  NAV_WAIT_MS   = Integer(ENV["NAV_WAIT_MS"]   || 2_500)
  STEP_PAUSE_MS = Integer(ENV["STEP_PAUSE_MS"] || 0)
  # Browser to drive: chromium (default), firefox, or webkit. Each must be
  # installed via `npx playwright install <browser>`.
  BROWSER = (ENV["BROWSER"].presence || "chromium").downcase
  raise "Unknown BROWSER=#{BROWSER.inspect} (chromium|firefox|webkit)" unless %w[chromium firefox webkit].include?(BROWSER)
  # Where to POST results. Defaults to prod so cron runs hit the live DB.
  # Override with SMOKE_API_URL for local testing.
  API_URL     = ENV["SMOKE_API_URL"] || "https://agent44-app.fly.dev"
  # Public-facing host used for email links (developer will see these).
  PUBLIC_HOST = ENV["NYK_PUBLIC_HOST"] || "https://agent44labs.com"
  VLAD_AGENT  = "Vlad ✅"
  DEBUG_NAV   = ENV["DEBUG_NAV"] == "true"
  # Network requests to these hosts are tracked; everything else (analytics,
  # ads, fonts) is filtered out of the failure-email console diagnostics.
  RELEVANT_FAILURE_HOSTS = %w[nykitchen.com www.nykitchen.com].freeze

  def self.runnable_methods
    ENV["RUN_SMOKE"] == "true" ? super : []
  end

  setup do
    FileUtils.mkdir_p(ARTIFACT_DIR)
    @stamp = Time.now.strftime("%Y%m%d-%H%M%S")
    @video_dir = ARTIFACT_DIR.join("videos-#{@stamp}")
    @screenshot_path = ARTIFACT_DIR.join("#{self.class::ARTIFACT_PREFIX}-#{@stamp}.png")
    @trace_path = ARTIFACT_DIR.join("#{self.class::ARTIFACT_PREFIX}-#{@stamp}.trace.zip")
    @failures = []
    @console_errors = []        # populated via page.on("console")/("pageerror") hooks
    @printed_console_lines = Set.new # dedupe GA log spam
    @steps = []                 # plain-English step log for the failure email
    @page_source_path = nil
    @calendar_url_at_failure = nil
    @user_agent = nil
    @started_at = Time.now
    update_vlad_status("busy", "NY Kitchen smoke test")
  end

  teardown do
    update_vlad_status("online")
  end

  protected

  # ---------------------------------------------------------------------------
  # Vlad status (the dashboard agent that shows what the smoke test is doing)
  # ---------------------------------------------------------------------------

  def update_vlad_status(status, task = nil, retries: 3)
    token = ENV["API_TOKEN"]
    return if token.to_s.empty?

    name = URI.encode_uri_component(VLAD_AGENT)
    uri = URI("#{API_URL}/api/v1/agents/#{name}/status")
    body = { status: status, current_task: task }.compact.to_json

    retries.times do |attempt|
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 10

      req = Net::HTTP::Patch.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Content-Type"] = "application/json"
      req.body = body

      res = http.request(req)
      if res.is_a?(Net::HTTPSuccess)
        puts "  🤖 Vlad → #{status}#{task ? " (#{task})" : ""}"
        verify_vlad_status(status) if ENV["VERIFY_VLAD_STATUS"] == "true"
        return
      else
        puts "  ⚠  Vlad status update → HTTP #{res.code} (attempt #{attempt + 1}/#{retries})"
      end
    rescue => e
      puts "  ⚠  Vlad status update error: #{e.class}: #{e.message} (attempt #{attempt + 1}/#{retries})"
      sleep 2 if attempt < retries - 1
    end

    @failures << "Vlad status update to '#{status}' failed after #{retries} attempts" if ENV["VERIFY_VLAD_STATUS"] == "true"
  end

  def verify_vlad_status(expected_status)
    uri = URI("#{API_URL}/api/v1/agents/statuses")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 5

    res = http.request(Net::HTTP::Get.new(uri))
    agents = JSON.parse(res.body)
    vlad = agents.find { |a| a["name"] == VLAD_AGENT }

    if vlad.nil?
      puts "  ⚠  verify: Vlad agent not found in statuses response"
      @failures << "Vlad agent not found in /api/v1/agents/statuses"
    elsif vlad["status"] != expected_status
      puts "  ⚠  verify: expected Vlad '#{expected_status}', got '#{vlad["status"]}'"
      @failures << "Vlad status mismatch: expected '#{expected_status}', got '#{vlad["status"]}'"
    else
      puts "  ✅ verify: Vlad status confirmed '#{expected_status}' (Telegram notification triggered)"
    end
  rescue => e
    puts "  ⚠  verify error: #{e.class}: #{e.message}"
  end

  # ---------------------------------------------------------------------------
  # Playwright + page helpers
  # ---------------------------------------------------------------------------

  def playwright_cli
    path = Rails.root.join("node_modules", ".bin", "playwright")
    unless File.executable?(path)
      skip "Playwright CLI not found. Run: npm install playwright && npx playwright install chromium"
    end
    path.to_s
  end

  def event_selector
    ".tribe-events-calendar-month__calendar-event"
  end

  def nav_selector(direction)
    "a.tribe-events-c-top-bar__nav-link--#{direction == "previous" ? "prev" : "next"}"
  end

  def month_title_selector
    ".tribe-events-c-top-bar__datepicker-button, .tribe-events-calendar-month__header-title"
  end

  def read_month_title(page)
    page.locator(month_title_selector).first.inner_text.strip
  rescue
    ""
  end

  # See nyk_calendar_nav_test.rb for original docs. Returns array of
  # { id:, title: } symbol-key hashes, deduped by ID.
  def capture_events(page)
    raw = page.evaluate(<<~JS) || []
      Array.from(document.querySelectorAll('.tribe-events-calendar-month__calendar-event')).map(el => {
        const idMatch = el.className.match(/post-(\\d+)/);
        const linkEl = el.querySelector('.tribe-events-calendar-month__calendar-event-title-link, .tribe-events-calendar-month__calendar-event-title');
        return {
          id: idMatch ? idMatch[1] : null,
          title: linkEl ? linkEl.textContent.trim().replace(/\\s+/g, ' ') : ''
        };
      }).filter(e => e.id);
    JS
    raw
      .map { |e| { id: e["id"].to_s, title: e["title"].to_s } }
      .uniq { |e| e[:id] }
  end

  def click_nav(page, direction)
    before_title = read_month_title(page)
    before_url = page.url
    before_event_ids = capture_events(page).map { |e| e[:id] }.sort
    record_step(kind: "click", direction: direction)
    page.locator(nav_selector(direction)).first.click

    if DEBUG_NAV
      page.wait_for_timeout(3000)
      now_url = page.url
      puts "    🔍 DEBUG click_nav(#{direction}):"
      puts "       before url:   #{before_url}"
      puts "       after url:    #{now_url}"
      puts "       url changed?  #{now_url != before_url}"
      puts "       before title: #{before_title.inspect}"
      puts "       after title:  #{read_month_title(page).inspect}"
      puts "       before events: #{before_event_ids.size}"
      puts "       after events:  #{capture_events(page).map { |e| e[:id] }.sort.size}"
      puts "       body classes: #{page.evaluate("document.body.className")}"
    end

    deadline = Time.now + 15
    while Time.now < deadline
      title_changed = read_month_title(page) != before_title && !read_month_title(page).empty?
      now_ids = capture_events(page).map { |e| e[:id] }.sort
      events_changed = now_ids != before_event_ids
      break if title_changed && (events_changed || now_ids.any? || Time.now > deadline - 3)
      page.wait_for_timeout(250)
    end
    page.wait_for_load_state("networkidle", timeout: 5_000) rescue nil
    page.wait_for_timeout(NAV_WAIT_MS)

    final_title = read_month_title(page)
    final_ids   = capture_events(page).map { |e| e[:id] }.sort
    record_step(
      kind: "navigation_settled",
      direction: direction,
      title_after: final_title,
      events_after: final_ids.size,
      title_changed: final_title != before_title && !final_title.empty?,
      events_changed: final_ids != before_event_ids
    )
  end

  def record_step(kind:, **details)
    @steps << { at: Time.now, kind: kind, **details }
  end

  # Elementor's "Stay in the Loop" popup intercepts pointer events so the
  # calendar nav arrows can't be clicked. We hide only the popup-modal
  # elements by ID prefix — broader selectors (.dialog-widget) broke TEC's
  # AJAX event rendering entirely.
  def dismiss_newsletter_popup(page)
    page.evaluate(<<~JS)
      (function() {
        const style = document.createElement('style');
        style.textContent = `
          [id^="elementor-popup-modal-"] {
            display: none !important;
            pointer-events: none !important;
          }
        `;
        document.head.appendChild(style);
      })();
    JS
    page.wait_for_timeout(400)
  end

  def fail_with_artifacts(page, context, message)
    @page_source_path = ARTIFACT_DIR.join("#{self.class::ARTIFACT_PREFIX}-page-source-#{@stamp}.html")
    File.write(@page_source_path, page.content) rescue nil
    @calendar_url_at_failure = (page.url rescue TARGET_URL)
    @user_agent = (page.evaluate("navigator.userAgent") rescue "").to_s
    record_step(kind: "failure", reason: message.lines.first.to_s.strip)

    page.screenshot(path: @screenshot_path.to_s, fullPage: true) rescue nil
    context.tracing.stop(path: @trace_path.to_s) rescue nil
    context.close rescue nil

    puts "\n  📡 console_errors captured: #{@console_errors.size} entries"
    enriched = with_console_context(message)
    run_id = post_result(status: "failed", error_message: enriched)
    upload_video(run_id) if run_id

    short_msg = enriched.lines.first(2).join.strip[0, 240]
    progress_ping("🚨 Vlad — NYK smoke FAILED", body: short_msg, level: "error")

    page_source_url = run_id ? "#{PUBLIC_HOST}/nykitchen/smoke_runs/#{run_id}/page_source" : nil
    trace_url       = run_id ? "#{PUBLIC_HOST}/nykitchen/smoke_runs/#{run_id}/trace"       : nil

    preview_failure_email(
      message: message,
      console_errors: @console_errors.uniq,
      steps: @steps,
      calendar_url_at_failure: @calendar_url_at_failure,
      user_agent: @user_agent,
      run_id: run_id,
      page_source_url: page_source_url,
      trace_url: trace_url
    )

    flunk enriched
  end

  # ---------------------------------------------------------------------------
  # Telemetry
  # ---------------------------------------------------------------------------

  def progress_ping(title, body: nil, level: "info")
    return if ENV["VLAD_PROGRESS_PINGS"] == "false"
    token = ENV["API_TOKEN"]
    return if token.to_s.empty?

    uri = URI("#{API_URL}/api/v1/notifications")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 8

    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{token}"
    req["Content-Type"] = "application/json"
    req.body = { source: "smoke_progress", title: title, body: body, level: level, telegram: true }.compact.to_json

    res = http.request(req)
    if res.is_a?(Net::HTTPSuccess)
      puts "  📡 progress: #{title}"
    else
      puts "  ⚠  progress ping HTTP #{res.code}: #{res.body[0, 200]}"
    end
  rescue => e
    puts "  ⚠  progress ping error: #{e.class}: #{e.message}"
  end

  def log_console_line(line)
    @printed_console_lines ||= Set.new
    return unless @printed_console_lines.add?(line)
    puts "  #{line}"
  end

  def attach_console_listeners(page)
    page.on("console", ->(msg) {
      begin
        type = (msg.type rescue nil).to_s
        text = (msg.text rescue msg.to_s).to_s.strip
        log_console_line("🟦 console.#{type}: #{text[0, 160]}") if ENV["DEBUG_CONSOLE_LISTENERS"] == "true"
        if %w[error warning assert].include?(type) && text.length > 0
          @console_errors << "[console.#{type}] #{text}"
        end
      rescue => e
        puts "  ⚠  console listener error: #{e.class}: #{e.message}"
      end
    })

    page.on("pageerror", ->(err) {
      begin
        txt = (err.message rescue err.to_s).to_s.strip
        log_console_line("🟥 pageerror: #{txt[0, 160]}")
        @console_errors << "[pageerror] #{txt}" if txt.length > 0
      rescue => e
        puts "  ⚠  pageerror listener error: #{e.class}: #{e.message}"
      end
    })

    page.on("requestfailed", ->(req) {
      begin
        url = (req.url rescue "").to_s
        method = (req.method rescue "GET")
        reason = "request failed"
        begin
          f = req.failure
          reason = f["errorText"] if f.respond_to?(:[]) && f["errorText"]
        rescue
        end
        host = (URI.parse(url).host rescue "")
        if RELEVANT_FAILURE_HOSTS.include?(host)
          puts "  🟧 requestfailed: #{method} #{url} — #{reason}"
          @console_errors << "[requestfailed] #{method} #{url} — #{reason}"
        end
      rescue => e
        puts "  ⚠  requestfailed listener error: #{e.class}: #{e.message}"
      end
    })

    page.on("response", ->(res) {
      begin
        status = (res.status rescue 0).to_i
        if status >= 400
          url = (res.url rescue "").to_s
          host = (URI.parse(url).host rescue "")
          if RELEVANT_FAILURE_HOSTS.include?(host)
            puts "  🟨 response #{status}: #{url}"
            @console_errors << "[response #{status}] #{url}"
          end
        end
      rescue => e
        puts "  ⚠  response listener error: #{e.class}: #{e.message}"
      end
    })

    puts "  📡 console listeners attached (console/pageerror/requestfailed/response)"
  rescue => e
    puts "  ⚠  Could not attach console listeners: #{e.class}: #{e.message}"
  end

  def with_console_context(message)
    return message if @console_errors.nil? || @console_errors.empty?
    deduped = @console_errors.uniq.first(15)
    extra = "\n\nBrowser console during run (#{@console_errors.size} captured, #{deduped.size} unique shown):\n  • " + deduped.join("\n  • ")
    extra += "\n  • … (#{@console_errors.size - deduped.size} more)" if @console_errors.size > deduped.size
    message + extra
  end

  # ---------------------------------------------------------------------------
  # API: post run + snapshot, upload video
  # ---------------------------------------------------------------------------

  def post_result(status:, summary: nil, error_message: nil)
    token = ENV["API_TOKEN"]
    if token.to_s.empty?
      puts "  ⚠  API_TOKEN not set; skipping smoke-run POST"
      return
    end

    ended_at = Time.now
    console_errors = (@console_errors || []).uniq.join("\n").presence
    body = {
      name: self.class::TEST_NAME,
      status: status,
      started_at: @started_at.iso8601,
      ended_at: ended_at.iso8601,
      duration_ms: ((ended_at - @started_at) * 1000).to_i,
      summary: summary,
      error_message: error_message,
      console_errors: console_errors
    }.compact.to_json

    uri = URI("#{API_URL}/api/v1/smoke_runs")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10

    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{token}"
    req["Content-Type"] = "application/json"
    req.body = body

    res = http.request(req)
    if res.is_a?(Net::HTTPSuccess)
      data = JSON.parse(res.body) rescue {}
      puts "  📬 smoke-run posted to #{API_URL} (#{status})"
      return data["id"]
    else
      puts "  ⚠  smoke-run POST → HTTP #{res.code}: #{res.body.to_s[0, 200]}"
    end
    nil
  rescue => e
    puts "  ⚠  smoke-run POST error: #{e.class}: #{e.message}"
    nil
  end

  def post_kitchen_snapshot(events)
    token = ENV["API_TOKEN"]
    if token.to_s.empty?
      puts "  ⚠  API_TOKEN not set; skipping kitchen snapshot POST"
      return
    end

    body = {
      taken_on: Date.today.to_s,
      events: events
    }.to_json

    uri = URI("#{API_URL}/api/v1/kitchen_snapshots")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 30

    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{token}"
    req["Content-Type"] = "application/json"
    req.body = body

    res = http.request(req)
    if res.is_a?(Net::HTTPSuccess)
      data = JSON.parse(res.body) rescue {}
      puts "  📬 kitchen snapshot posted: #{data['events_created']} events (snapshot ##{data['snapshot_id']})"
    else
      puts "  ⚠  kitchen snapshot POST → HTTP #{res.code}: #{res.body.to_s[0, 200]}"
    end
  rescue => e
    puts "  ⚠  kitchen snapshot POST error: #{e.class}: #{e.message}"
  end

  def upload_video(run_id)
    video_path = Dir.glob(@video_dir.join("*.webm").to_s).first
    return unless video_path && File.exist?(video_path)

    update_vlad_status("busy", "Compressing video")
    compressed_path = ARTIFACT_DIR.join("smoke-#{@stamp}-compressed.webm").to_s
    system("ffmpeg", "-y", "-i", video_path,
           "-c:v", "libvpx-vp9", "-crf", "40", "-b:v", "200k",
           "-vf", "scale=960:-1", "-an",
           compressed_path,
           out: File::NULL, err: File::NULL)
    video_path = File.exist?(compressed_path) ? compressed_path : video_path

    thumb_path = ARTIFACT_DIR.join("thumb-#{@stamp}.jpg").to_s
    system("ffmpeg", "-y", "-i", video_path, "-ss", "00:00:05",
           "-vframes", "1", "-q:v", "2", thumb_path,
           out: File::NULL, err: File::NULL)

    token = ENV["API_TOKEN"]
    return if token.to_s.empty?

    uri = URI("#{API_URL}/api/v1/smoke_runs/#{run_id}/video")
    boundary = "----SmokeUpload#{SecureRandom.hex(8)}"

    parts = []
    parts << multipart_file_part("video", video_path, "video/webm", boundary)
    if File.exist?(thumb_path)
      parts << multipart_file_part("thumbnail", thumb_path, "image/jpeg", boundary)
    end
    if @page_source_path && File.exist?(@page_source_path.to_s)
      parts << multipart_file_part("page_source", @page_source_path.to_s, "text/html", boundary)
    end
    if @trace_path && File.exist?(@trace_path.to_s)
      parts << multipart_file_part("trace", @trace_path.to_s, "application/zip", boundary)
    end
    body = parts.join + "--#{boundary}--\r\n"

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 30

    req = Net::HTTP::Put.new(uri)
    req["Authorization"] = "Bearer #{token}"
    req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
    req.body = body

    res = http.request(req)
    if res.is_a?(Net::HTTPSuccess)
      size_mb = (File.size(video_path) / 1_048_576.0).round(1)
      puts "  🎬 video uploaded (#{size_mb} MB)"
    else
      puts "  ⚠  video upload → HTTP #{res.code}: #{res.body.to_s[0, 200]}"
    end
  rescue => e
    puts "  ⚠  video upload error: #{e.class}: #{e.message}"
  end

  def multipart_file_part(field, path, content_type, boundary)
    filename = File.basename(path)
    "--#{boundary}\r\n" \
    "Content-Disposition: form-data; name=\"#{field}\"; filename=\"#{filename}\"\r\n" \
    "Content-Type: #{content_type}\r\n\r\n" \
    "#{File.binread(path)}\r\n"
  end

  def preview_failure_email(message:, console_errors: nil,
                            steps: nil, calendar_url_at_failure: nil,
                            user_agent: nil, run_id: nil,
                            page_source_url: nil, trace_url: nil)
    deliver = ENV["NYK_SMOKE_DELIVER"] == "true"

    if deliver && ENV["BREVO_SMTP_KEY"].present?
      ActionMailer::Base.delivery_method = :smtp
      ActionMailer::Base.smtp_settings = {
        address: "smtp-relay.brevo.com",
        port: 587,
        user_name: ENV.fetch("BREVO_SMTP_LOGIN", "a5ec98001@smtp-brevo.com"),
        password: ENV["BREVO_SMTP_KEY"],
        authentication: :plain,
        enable_starttls_auto: true
      }
      ActionMailer::Base.raise_delivery_errors = true
    end

    mail = NykSmokeMailer.failure(
      failure_message: message,
      started_at: Time.now,
      recipients: ENV["NYK_SMOKE_RECIPIENTS"] || "preview@example.com",
      console_errors: console_errors,
      steps: steps,
      calendar_url_at_failure: calendar_url_at_failure,
      user_agent: user_agent,
      runner_name: ENV["RUNNER_NAME"].presence || (Socket.gethostname rescue "unknown"),
      run_id: run_id,
      page_source_url: page_source_url,
      trace_url: trace_url
    )

    html_path = ARTIFACT_DIR.join("#{self.class::ARTIFACT_PREFIX}-preview-#{@stamp}.html")
    File.write(html_path, mail.html_part&.body&.to_s || mail.body.to_s)

    puts "\n" + "=" * 70
    puts deliver ? "📧 NY Kitchen smoke EMAIL — DELIVERING" : "📧 NY Kitchen smoke EMAIL PREVIEW (not sent)"
    puts "=" * 70
    puts "SUBJECT: #{mail.subject}"
    puts "TO:      #{Array(mail.to).join(", ")}"
    puts "FROM:    #{Array(mail.from).join(", ")}"
    puts
    puts "Artifacts:"
    puts "  page_source: #{page_source_url || '(no run_id)'}"
    puts "  trace:       #{trace_url || '(no run_id)'}"
    puts "  html body:   #{html_path}"
    puts "=" * 70

    if deliver
      if ENV["BREVO_SMTP_KEY"].to_s.empty?
        puts "✗ BREVO_SMTP_KEY not set — cannot actually send (pull from Fly: fly ssh console -C 'printenv BREVO_SMTP_KEY')"
      else
        mail.deliver_now
        puts "✉️  Delivered via Brevo."
      end
    else
      puts "(set NYK_SMOKE_DELIVER=true to actually send)"
    end
    puts
  end
end
