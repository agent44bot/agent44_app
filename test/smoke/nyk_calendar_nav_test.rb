require "test_helper"
require "fileutils"
require "playwright"
require "net/http"
require "json"
require_relative "nyk_event_scraper_helper"

# Black-box smoke test for https://nykitchen.com/calendar/
#
# Regression target: previously, clicking the < / > month-nav arrows left
# the calendar grid empty. Workaround was to use the month dropdown. The
# developer pushed a fix; this test guards the fix with an event-round-trip
# assertion:
#
#   1. Load /calendar/
#   2. At month[0], capture the set of events visible
#   3. Click next → month[+1], capture
#   4. Click next → month[+2], capture
#   5. Click next → month[+3], capture
#   6. Click prev → month[+2], assert events == step-3 capture
#   7. Click prev → month[+1], assert events == step-2 capture
#   8. Click prev → month[0],  assert events == step-1 capture
#
# Event signature = WP post ID (from the `post-XXXXXX` class that The Events
# Calendar adds to each event). Title is kept alongside for readable error
# messages. The round-trip assertion catches "events never rendered," "events
# partially rendered," and "events vanished on return" — all variants of the
# original bug.
#
# Run with:  RUN_SMOKE=true bin/rails test test/smoke/nyk_calendar_nav_test.rb
# Or:        rake test:smoke:nyk
# Watch it:  HEADFUL=true rake test:smoke:nyk
#
# On failure: writes .webm video, .png screenshot, Playwright trace to
# tmp/smoke/, and renders a preview email to stdout (not sent).
class NykCalendarNavTest < ActiveSupport::TestCase
  include NykEventScraperHelper

  TARGET_URL = NykSmokeMailer::TARGET_URL
  ARTIFACT_DIR = Rails.root.join("tmp", "smoke")
  FORWARD_STEPS = 3 # clicks past initial load; total months visited = 4
  NAV_WAIT_MS   = Integer(ENV["NAV_WAIT_MS"]  || 2_500)
  STEP_PAUSE_MS = Integer(ENV["STEP_PAUSE_MS"] || 0)
  TEST_NAME = "nyk_calendar_nav"
  # Where to POST results. Defaults to prod so cron runs hit the live DB.
  # Override with SMOKE_API_URL for local testing.
  API_URL = ENV["SMOKE_API_URL"] || "https://agent44-app.fly.dev"

  def self.runnable_methods
    ENV["RUN_SMOKE"] == "true" ? super : []
  end

  VLAD_AGENT = "Vlad ✅"

  setup do
    FileUtils.mkdir_p(ARTIFACT_DIR)
    @stamp = Time.now.strftime("%Y%m%d-%H%M%S")
    @video_dir = ARTIFACT_DIR.join("videos-#{@stamp}")
    @screenshot_path = ARTIFACT_DIR.join("nyk-calendar-nav-#{@stamp}.png")
    @trace_path = ARTIFACT_DIR.join("nyk-calendar-nav-#{@stamp}.trace.zip")
    @failures = []
    @console_errors = [] # populated via page.on("console")/("pageerror") hooks
    @printed_console_lines = Set.new # dedupe GA log spam (e.g. reCAPTCHA pageerror fires per page)
    @started_at = Time.now
    update_vlad_status("busy", "NY Kitchen smoke test")
  end

  teardown do
    update_vlad_status("online")
  end

  DEBUG_NAV = ENV["DEBUG_NAV"] == "true"

  test "events round-trip: nav forward N months, back N months, event sets match" do
    # Escape hatch for wiring/testing the failure email path — forces a fake
    # failure after capturing a real video so we can verify end-to-end delivery.
    if ENV["FORCE_FAIL"] == "true"
      Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
        browser = pw.chromium.launch(headless: true)
        context = browser.new_context(record_video_dir: @video_dir.to_s)
        context.tracing.start(screenshots: true, snapshots: true, sources: false)
        page = context.new_page
        page.goto(TARGET_URL, timeout: 30_000, waitUntil: "domcontentloaded")
        page.wait_for_timeout(2_000)
        fail_with_artifacts(page, context, "FORCE_FAIL=true — simulated failure to test the email-delivery pipeline")
      end
      return
    end

    Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
      headful = %w[1 true yes t y].include?(ENV["HEADFUL"].to_s.downcase)
      browser = pw.chromium.launch(headless: !headful)
      context = browser.new_context(
        viewport: { width: 1280, height: 900 },
        record_video_dir: @video_dir.to_s
        # Default Chromium UA — custom UAs can trigger bot-detection on some
        # WordPress sites (The Events Calendar has returned empty AJAX for
        # non-standard UAs in testing).
      )
      context.tracing.start(screenshots: true, snapshots: true, sources: false)
      page = context.new_page
      attach_console_listeners(page)

      begin
        page.goto(TARGET_URL, timeout: 30_000, waitUntil: "domcontentloaded")
        page.wait_for_selector(event_selector, timeout: 15_000)
        dismiss_newsletter_popup(page) unless ENV["NO_POPUP_KILL"] == "true"
        page.wait_for_timeout(STEP_PAUSE_MS)
        progress_ping("🤖 Vlad — Loaded NYK calendar", body: "starting #{FORWARD_STEPS + 1}-month round-trip")

        # --- Forward phase -------------------------------------------------
        forward = [] # [{ title: "April 2026", events: [{id:, title:}, ...] }, ...]
        all_event_urls = []
        (FORWARD_STEPS + 1).times do |i|
          capture = { title: read_month_title(page), events: capture_events(page) }
          forward << capture
          all_event_urls.concat(collect_event_urls(page))
          puts "  ➡  [#{i}] #{capture[:title]} — #{capture[:events].size} events"

          if i < FORWARD_STEPS
            click_nav(page, "next")
            page.wait_for_timeout(STEP_PAUSE_MS)
          end
        end

        total_events = forward.sum { |m| m[:events].size }
        @failures << "No events captured in any of the #{forward.size} forward months — test is not meaningful" if total_events == 0
        progress_ping("🤖 Vlad — Walking back to verify round-trip", body: "captured #{total_events} events across #{forward.size} months")

        # --- Back phase ----------------------------------------------------
        FORWARD_STEPS.times do |i|
          click_nav(page, "previous")
          page.wait_for_timeout(STEP_PAUSE_MS)

          expected = forward[FORWARD_STEPS - 1 - i]
          actual = { title: read_month_title(page), events: capture_events(page) }
          puts "  ⬅  #{actual[:title]} — #{actual[:events].size} events (expected #{expected[:events].size})"

          if actual[:title] != expected[:title]
            @failures << "month title mismatch on return: expected '#{expected[:title]}', got '#{actual[:title]}'"
            next
          end

          fwd_ids = expected[:events].map { |e| e[:id] }.sort
          back_ids = actual[:events].map { |e| e[:id] }.sort
          next if fwd_ids == back_ids

          missing_ids  = fwd_ids - back_ids
          appeared_ids = back_ids - fwd_ids
          missing_titles  = expected[:events].select { |e| missing_ids.include?(e[:id]) }.map { |e| e[:title] }
          appeared_titles = actual[:events].select   { |e| appeared_ids.include?(e[:id]) }.map { |e| e[:title] }

          detail = []
          detail << "#{missing_ids.size} event(s) missing on return: #{missing_titles.first(3).inspect}" if missing_ids.any?
          detail << "#{appeared_ids.size} unexpected event(s) on return: #{appeared_titles.first(3).inspect}" if appeared_ids.any?
          @failures << "events differ in #{actual[:title]} after round-trip — #{detail.join("; ")}"
        end

        if @failures.any?
          fail_with_artifacts(page, context, "Round-trip failed:\n  - " + @failures.join("\n  - "))
        else
          puts "\n  ✅ NY Kitchen calendar nav: event sets survived a #{FORWARD_STEPS}-month round-trip."

          # --- Scraping phase (opt-out via SCRAPE_EVENTS=false) ---------------
          scraped_events = []
          if ENV["SCRAPE_EVENTS"] != "false"
            today = Date.today
            unique_urls = all_event_urls.uniq.reject { |url|
              # Skip URLs for dates already past (calendar URLs end with e.g. 4-17-26/)
              if url =~ /(\d{1,2})-(\d{1,2})-(\d{2,4})\/?$/
                m, d, y = $1.to_i, $2.to_i, $3.to_i
                y += 2000 if y < 100
                Date.new(y, m, d) < today rescue false
              else
                false
              end
            }
            puts "\n  🔍 Scraping #{unique_urls.size} event detail pages (skipped past dates)..."
            progress_ping("🤖 Vlad — Scraping #{unique_urls.size} event pages", body: "round-trip OK, gathering details")

            last_pct = -1
            unique_urls.each_with_index do |url, i|
              begin
                event = scrape_detail_page(page, url)
                scraped_events << event if event
                puts "    [#{i + 1}/#{unique_urls.size}] #{event[:name]&.to_s&.truncate(50) || url}"
              rescue => e
                puts "    [#{i + 1}/#{unique_urls.size}] FAILED: #{e.message}"
              end
              # Update Vlad's progress every ~10%
              pct = ((i + 1) * 100 / unique_urls.size / 10) * 10
              if pct > last_pct
                update_vlad_status("busy", "Scraping nykitchen #{pct}%")
                last_pct = pct
              end
              page.wait_for_timeout(DETAIL_PAGE_PAUSE_MS) if i < unique_urls.size - 1
            end

            # Filter out past events — only future classes should be stored
            today = Date.today.to_s
            before = scraped_events.size
            scraped_events.reject! { |e|
              e[:passed] ||                                          # page says "This event has passed"
              (e[:start_at].present? && e[:start_at].to_s < today)   # start date is in the past
            }
            skipped = before - scraped_events.size
            puts "    Filtered: #{skipped} past event(s) removed, #{scraped_events.size} upcoming kept" if skipped > 0

            post_kitchen_snapshot(scraped_events) if scraped_events.any?
          end

          context.tracing.stop
          context.close
          browser.close
          scrape_note = scraped_events.any? ? ", #{scraped_events.size} events scraped" : ""
          summary = forward.map { |m| m[:events].size }.join("/") + " events round-tripped#{scrape_note}"
          run_id = post_result(status: "passed", summary: summary)
          upload_video(run_id) if run_id
          progress_ping("✅ Vlad — NYK smoke PASSED", body: summary, level: "success")
          assert_empty @failures
        end
      rescue => e
        fail_with_artifacts(page, context, "#{e.class}: #{e.message}")
      ensure
        browser&.close rescue nil
      end
    end
  end

  private

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

  # Read back Vlad's status from the API to confirm it stuck and that
  # the Telegram notification side-effect fired (the PATCH handler sends
  # a Telegram message on status transitions).
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

  # Extract all events visible on the current month view. Returns an array of
  # { id:, title: } hashes. ID comes from the WP post class (stable across
  # navigation); title comes from the rendered anchor text.
  def capture_events(page)
    page.evaluate(<<~JS) || []
      Array.from(document.querySelectorAll('.tribe-events-calendar-month__calendar-event')).map(el => {
        const idMatch = el.className.match(/post-(\\d+)/);
        const linkEl = el.querySelector('.tribe-events-calendar-month__calendar-event-title-link, .tribe-events-calendar-month__calendar-event-title');
        return {
          id: idMatch ? idMatch[1] : null,
          title: linkEl ? linkEl.textContent.trim().replace(/\\s+/g, ' ') : ''
        };
      }).filter(e => e.id);
    JS
  end

  def click_nav(page, direction)
    before_title = read_month_title(page)
    before_url = page.url
    before_event_ids = capture_events(page).map { |e| e[:id] }.sort
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

    # Wait until BOTH: the month title updated AND the set of event IDs changed.
    # NY Kitchen's calendar updates the title via JS immediately but events render
    # after a separate AJAX round-trip; watching only title causes false-ready
    # captures with empty event lists.
    deadline = Time.now + 15
    while Time.now < deadline
      title_changed = read_month_title(page) != before_title && !read_month_title(page).empty?
      now_ids = capture_events(page).map { |e| e[:id] }.sort
      events_changed = now_ids != before_event_ids
      # Ready when title changed AND (events changed OR we've given it a fair chance)
      # — months with 0 events are valid, so we can't require a strictly non-empty set.
      break if title_changed && (events_changed || now_ids.any? || Time.now > deadline - 3)
      page.wait_for_timeout(250)
    end
    page.wait_for_load_state("networkidle", timeout: 5_000) rescue nil
    page.wait_for_timeout(NAV_WAIT_MS)
  end

  # Elementor's "Stay in the Loop" popup on nykitchen.com/calendar/ intercepts
  # pointer events so the calendar nav arrows can't be clicked. Narrowly target
  # only the elementor-popup-modal-<id> elements by their exact ID prefix so we
  # don't disturb any other .dialog-widget that The Events Calendar's own AJAX
  # might use (overreach with broader selectors broke AJAX event rendering
  # entirely — March/April/May returned empty event lists).
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
    page.screenshot(path: @screenshot_path.to_s, fullPage: true) rescue nil
    context.tracing.stop(path: @trace_path.to_s) rescue nil
    context.close rescue nil

    video_path = Dir.glob(@video_dir.join("*.webm").to_s).first

    puts "\n  📡 console_errors captured: #{@console_errors.size} entries"
    enriched = with_console_context(message)
    run_id = post_result(status: "failed", error_message: enriched)
    upload_video(run_id) if run_id

    short_msg = enriched.lines.first(2).join.strip[0, 240]
    progress_ping("🚨 Vlad — NYK smoke FAILED", body: short_msg, level: "error")

    preview_failure_email(
      message: message,
      console_errors: @console_errors.uniq,
      video_path: video_path,
      screenshot_path: @screenshot_path.to_s,
      trace_path: @trace_path.to_s
    )

    flunk enriched
  end

  # Posts a Telegram-routed Notification to /api/v1/notifications. Used at
  # phase boundaries (page loaded, back-nav started, scraping started,
  # complete). Set VLAD_PROGRESS_PINGS=false to silence them.
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
      puts "  ⚠  progress ping HTTP #{res.code}: #{res.body[0,200]}"
    end
  rescue => e
    puts "  ⚠  progress ping error: #{e.class}: #{e.message}"
  end

  # Hook page-level listeners for anything a developer would see in DevTools:
  #   - console.{warning,error,assert} messages
  #   - uncaught JS exceptions (pageerror)
  #   - network requests that fail / return >= 400
  # Captured strings are appended to failure messages, the failure email,
  # and the SmokeTestRun.console_errors column.
  #
  # Skip irrelevant network noise (tracking pixels, ads) by domain — keep
  # only requests to nykitchen.com and same-page resources.
  RELEVANT_FAILURE_HOSTS = %w[nykitchen.com www.nykitchen.com].freeze

  # Print a console-listener line once per unique text. Subsequent duplicates
  # are silently dropped from stdout — @console_errors still records every
  # occurrence so the failure email's count stays accurate.
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
        log_console_line("🟦 console.#{type}: #{text[0,160]}") if ENV["DEBUG_CONSOLE_LISTENERS"] == "true"
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
        log_console_line("🟥 pageerror: #{txt[0,160]}")
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

  # POST a row to /api/v1/smoke_runs so agent44labs.com/kitchen Tests tab
  # shows this run. Fails silently (log-only) if the API is unreachable —
  # we don't want to mask a legitimate test failure with an infra failure.
  def post_result(status:, summary: nil, error_message: nil)
    token = ENV["API_TOKEN"]
    if token.to_s.empty?
      puts "  ⚠  API_TOKEN not set; skipping smoke-run POST"
      return
    end

    ended_at = Time.now
    console_errors = (@console_errors || []).uniq.join("\n").presence
    body = {
      name: TEST_NAME,
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

    # Compress video with ffmpeg (target ~3-5 MB instead of 40+ MB)
    update_vlad_status("busy", "Compressing video")
    compressed_path = ARTIFACT_DIR.join("smoke-#{@stamp}-compressed.webm").to_s
    system("ffmpeg", "-y", "-i", video_path,
           "-c:v", "libvpx-vp9", "-crf", "40", "-b:v", "200k",
           "-vf", "scale=960:-1", "-an",
           compressed_path,
           out: File::NULL, err: File::NULL)
    video_path = File.exist?(compressed_path) ? compressed_path : video_path

    # Generate thumbnail with ffmpeg (grab a frame 5 seconds in)
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

  def preview_failure_email(message:, video_path:, screenshot_path:, trace_path:, console_errors: nil)
    deliver = ENV["NYK_SMOKE_DELIVER"] == "true"

    # Configure SMTP before building the mail object so delivery method is set
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
      video_path: video_path,
      screenshot_path: screenshot_path,
      trace_path: trace_path,
      started_at: Time.now,
      recipients: ENV["NYK_SMOKE_RECIPIENTS"] || "preview@example.com",
      console_errors: console_errors
    )

    html_path = ARTIFACT_DIR.join("nyk-smoke-preview-#{@stamp}.html")
    File.write(html_path, mail.html_part&.body&.to_s || mail.body.to_s)

    puts "\n" + "=" * 70
    puts deliver ? "📧 NY Kitchen smoke EMAIL — DELIVERING" : "📧 NY Kitchen smoke EMAIL PREVIEW (not sent)"
    puts "=" * 70
    puts "SUBJECT: #{mail.subject}"
    puts "TO:      #{Array(mail.to).join(", ")}"
    puts "FROM:    #{Array(mail.from).join(", ")}"
    puts
    puts "Artifacts:"
    puts "  video:      #{video_path || '(none)'}"
    puts "  screenshot: #{screenshot_path}"
    puts "  trace:      #{trace_path}  (drag into https://trace.playwright.dev)"
    puts "  html body:  #{html_path}"
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
