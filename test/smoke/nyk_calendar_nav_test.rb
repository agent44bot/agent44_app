require "test_helper"
require "fileutils"
require "playwright"

# Black-box smoke test for https://nykitchen.com/calendar/
#
# Regression target: previously, clicking the < / > month-nav arrows left
# the calendar grid empty (events didn't render). Workaround was to use the
# month dropdown instead. The developer pushed a fix; this test guards the fix.
#
# Run with:  RUN_SMOKE=true bin/rails test test/smoke/nyk_calendar_nav_test.rb
# Or:        rake test:smoke:nyk
#
# On failure: writes a .webm video, a .png screenshot, and a Playwright trace
# to tmp/smoke/, then renders a preview email to stdout (not sent). The mailer
# call is commented in; flip the comment and set recipients when ready to email.
class NykCalendarNavTest < ActiveSupport::TestCase
  TARGET_URL = "https://nykitchen.com/calendar/"
  ARTIFACT_DIR = Rails.root.join("tmp", "smoke")
  MIN_DAY_CELLS = 28 # full month grid has 28–42 day cells
  NAV_WAIT_MS  = Integer(ENV["NAV_WAIT_MS"]  || 2_500) # pause after each arrow click
  STEP_PAUSE_MS = Integer(ENV["STEP_PAUSE_MS"] || 0)   # extra pause for demo watching

  def self.runnable_methods
    ENV["RUN_SMOKE"] == "true" ? super : []
  end

  setup do
    FileUtils.mkdir_p(ARTIFACT_DIR)
    @stamp = Time.now.strftime("%Y%m%d-%H%M%S")
    @video_dir = ARTIFACT_DIR.join("videos-#{@stamp}") # Playwright requires a directory
    @screenshot_path = ARTIFACT_DIR.join("nyk-calendar-nav-#{@stamp}.png")
    @trace_path = ARTIFACT_DIR.join("nyk-calendar-nav-#{@stamp}.trace.zip")
    @failures = []
  end

  test "arrow nav renders calendar grid across prev, current, and next months" do
    Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
      browser = pw.chromium.launch(headless: ENV["HEADFUL"] != "true")
      context = browser.new_context(
        viewport: { width: 1280, height: 900 },
        record_video_dir: @video_dir.to_s,
        userAgent: "Agent44SmokeTest/1.0 (+https://agent44labs.com)"
      )
      context.tracing.start(screenshots: true, snapshots: true, sources: false)
      page = context.new_page

      begin
        page.goto(TARGET_URL, timeout: 30_000, waitUntil: "domcontentloaded")
        page.wait_for_selector(day_cell_selector, timeout: 15_000)
        dismiss_newsletter_popup(page)
        page.wait_for_timeout(STEP_PAUSE_MS)

        initial_month = read_month_title(page)
        assert_calendar_rendered(page, "initial load")

        click_nav(page, "previous")
        page.wait_for_timeout(STEP_PAUSE_MS)
        assert_month_changed(page, from: initial_month, label: "after clicking previous")
        assert_calendar_rendered(page, "after clicking previous")
        prev_month = read_month_title(page)

        click_nav(page, "next")
        page.wait_for_timeout(STEP_PAUSE_MS)
        assert_month_changed(page, from: prev_month, label: "after clicking next (back to current)")
        assert_calendar_rendered(page, "after clicking next (back to current)")
        current_again = read_month_title(page)

        click_nav(page, "next")
        page.wait_for_timeout(STEP_PAUSE_MS)
        assert_month_changed(page, from: current_again, label: "after clicking next (future month)")
        assert_calendar_rendered(page, "after clicking next (future month)")

        page.wait_for_timeout(STEP_PAUSE_MS) # let viewer see final state

        if @failures.any?
          fail_with_artifacts(page, context, "Assertions failed:\n  - " + @failures.join("\n  - "))
        else
          context.tracing.stop
          context.close
          browser.close
          assert_empty @failures, "Unexpected: failures should have triggered fail_with_artifacts"
          puts "\n  ✅ NY Kitchen calendar nav: all 3 arrow clicks rendered the grid."
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
    # Shim points at the Node-installed playwright CLI
    path = Rails.root.join("node_modules", ".bin", "playwright")
    unless File.executable?(path)
      skip "Playwright CLI not found. Run: npm install playwright && npx playwright install chromium"
    end
    path.to_s
  end

  def day_cell_selector
    # The Events Calendar (Modern Tribe) renders this class on every day cell in month view
    ".tribe-events-calendar-month__day"
  end

  def nav_selector(direction)
    # Real element is an <a> anchor with a CSS class that's stable across
    # The Events Calendar versions. Using the class avoids matching:
    #   - the datepicker popup's own prev/next (opens inside the year-grid modal)
    #   - any aria-label collisions with gallery/other nav
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

  def assert_calendar_rendered(page, label)
    count = page.locator(day_cell_selector).count
    if count < MIN_DAY_CELLS
      @failures << "#{label}: expected >= #{MIN_DAY_CELLS} day cells, got #{count}"
    end
  end

  def assert_month_changed(page, from:, label:)
    current = read_month_title(page)
    if current == from || current.empty?
      @failures << "#{label}: month title did not change (was '#{from}', now '#{current}')"
    end
  end

  def click_nav(page, direction)
    page.locator(nav_selector(direction)).first.click
    page.wait_for_timeout(NAV_WAIT_MS) # give AJAX time to refresh grid
    page.wait_for_selector(day_cell_selector, timeout: 10_000)
  end

  # The Events Calendar page has an Elementor newsletter popup ("STAY IN
  # THE LOOP") that intercepts pointer events. A one-shot DOM remove isn't
  # enough because Elementor reinjects it on a setTimeout. Set up a
  # MutationObserver that kills the popup every time it's added.
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
    page.wait_for_timeout(800) # let the observer catch any in-flight injection
  end

  def fail_with_artifacts(page, context, message)
    page.screenshot(path: @screenshot_path.to_s, fullPage: true) rescue nil
    context.tracing.stop(path: @trace_path.to_s) rescue nil
    context.close rescue nil

    # Video lands in @video_dir with an autogenerated name
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
