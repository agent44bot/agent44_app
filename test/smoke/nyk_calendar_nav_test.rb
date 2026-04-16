require "test_helper"
require "fileutils"
require "playwright"

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
  TARGET_URL = "https://nykitchen.com/calendar/"
  ARTIFACT_DIR = Rails.root.join("tmp", "smoke")
  FORWARD_STEPS = 3 # clicks past initial load; total months visited = 4
  NAV_WAIT_MS   = Integer(ENV["NAV_WAIT_MS"]  || 2_500)
  STEP_PAUSE_MS = Integer(ENV["STEP_PAUSE_MS"] || 0)

  def self.runnable_methods
    ENV["RUN_SMOKE"] == "true" ? super : []
  end

  setup do
    FileUtils.mkdir_p(ARTIFACT_DIR)
    @stamp = Time.now.strftime("%Y%m%d-%H%M%S")
    @video_dir = ARTIFACT_DIR.join("videos-#{@stamp}")
    @screenshot_path = ARTIFACT_DIR.join("nyk-calendar-nav-#{@stamp}.png")
    @trace_path = ARTIFACT_DIR.join("nyk-calendar-nav-#{@stamp}.trace.zip")
    @failures = []
  end

  test "events round-trip: nav forward N months, back N months, event sets match" do
    Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
      headful = %w[1 true yes t y].include?(ENV["HEADFUL"].to_s.downcase)
      browser = pw.chromium.launch(headless: !headful)
      context = browser.new_context(
        viewport: { width: 1280, height: 900 },
        record_video_dir: @video_dir.to_s,
        userAgent: "Agent44SmokeTest/1.0 (+https://agent44labs.com)"
      )
      context.tracing.start(screenshots: true, snapshots: true, sources: false)
      page = context.new_page

      begin
        page.goto(TARGET_URL, timeout: 30_000, waitUntil: "domcontentloaded")
        page.wait_for_selector(event_selector, timeout: 15_000)
        dismiss_newsletter_popup(page)
        page.wait_for_timeout(STEP_PAUSE_MS)

        # --- Forward phase -------------------------------------------------
        forward = [] # [{ title: "April 2026", events: [{id:, title:}, ...] }, ...]
        (FORWARD_STEPS + 1).times do |i|
          capture = { title: read_month_title(page), events: capture_events(page) }
          forward << capture
          puts "  ➡  [#{i}] #{capture[:title]} — #{capture[:events].size} events"

          if i < FORWARD_STEPS
            click_nav(page, "next")
            page.wait_for_timeout(STEP_PAUSE_MS)
          end
        end

        total_events = forward.sum { |m| m[:events].size }
        @failures << "No events captured in any of the #{forward.size} forward months — test is not meaningful" if total_events == 0

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
          context.tracing.stop
          context.close
          browser.close
          assert_empty @failures
          puts "\n  ✅ NY Kitchen calendar nav: event sets survived a #{FORWARD_STEPS}-month round-trip."
        end
      rescue => e
        fail_with_artifacts(page, context, "#{e.class}: #{e.message}")
      ensure
        browser&.close rescue nil
      end
    end
  end

  private

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
    page.locator(nav_selector(direction)).first.click
    page.wait_for_timeout(NAV_WAIT_MS)
    page.wait_for_load_state("networkidle", timeout: 10_000) rescue nil
  end

  # The Events Calendar page has an Elementor newsletter popup ("STAY IN
  # THE LOOP") that intercepts pointer events. Elementor reinjects it on a
  # setTimeout, so use a MutationObserver to kill it every time it appears.
  def dismiss_newsletter_popup(page)
    page.evaluate(<<~JS)
      (function() {
        const kill = () => {
          document.querySelectorAll(
            '.elementor-popup-modal, .dialog-widget, .dialog-lightbox-widget, [id^="elementor-popup-modal-"]'
          ).forEach(el => el.remove());
          document.body.classList.remove('elementor-popup-modal-open');
          document.body.style.overflow = '';
        };
        kill();
        new MutationObserver(kill).observe(document.body, { childList: true, subtree: true });
      })();
    JS
    page.wait_for_timeout(800)
  end

  def fail_with_artifacts(page, context, message)
    page.screenshot(path: @screenshot_path.to_s, fullPage: true) rescue nil
    context.tracing.stop(path: @trace_path.to_s) rescue nil
    context.close rescue nil

    video_path = Dir.glob(@video_dir.join("*.webm").to_s).first

    preview_failure_email(
      message: message,
      video_path: video_path,
      screenshot_path: @screenshot_path.to_s,
      trace_path: @trace_path.to_s
    )

    flunk message
  end

  def preview_failure_email(message:, video_path:, screenshot_path:, trace_path:)
    mail = NykSmokeMailer.failure(
      failure_message: message,
      video_path: video_path,
      screenshot_path: screenshot_path,
      trace_path: trace_path,
      started_at: Time.now,
      recipients: ENV["NYK_SMOKE_RECIPIENTS"] || "preview@example.com"
    )

    html_path = ARTIFACT_DIR.join("nyk-smoke-preview-#{@stamp}.html")
    File.write(html_path, mail.html_part&.body&.to_s || mail.body.to_s)

    puts "\n" + "=" * 70
    puts "📧 NY Kitchen smoke EMAIL PREVIEW (not sent)"
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
    puts
  end
end
