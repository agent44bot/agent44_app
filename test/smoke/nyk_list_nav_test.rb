require "test_helper"
require "fileutils"
require "playwright"

# Smoke test for NY Kitchen calendar LIST VIEW navigation.
#
# Bug report: clicking "Next Events >" in list view does nothing.
#
# Round-trip test (mirrors the month nav smoke test pattern):
#   1. Load /calendar/ and switch to List view
#   2. Capture the initial page of events
#   3. Click "Next Events >" N times, capturing each page
#   4. Click "Previous Events <" N times, verifying each page matches
#      the corresponding forward capture
#
# Run with:  RUN_SMOKE=true bin/rails test test/smoke/nyk_list_nav_test.rb
# Watch it:  HEADFUL=true RUN_SMOKE=true bin/rails test test/smoke/nyk_list_nav_test.rb
class NykListNavTest < ActiveSupport::TestCase
  TARGET_URL = "https://nykitchen.com/calendar/"
  ARTIFACT_DIR = Rails.root.join("tmp", "smoke")
  FORWARD_STEPS = 3 # pages past initial; total pages visited = 4

  def self.runnable_methods
    ENV["RUN_SMOKE"] == "true" ? super : []
  end

  setup do
    FileUtils.mkdir_p(ARTIFACT_DIR)
    @stamp = Time.now.strftime("%Y%m%d-%H%M%S")
    @failures = []
  end

  test "list view: round-trip forward N pages, back N pages, event sets match" do
    Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
      headful = %w[1 true yes t y].include?(ENV["HEADFUL"].to_s.downcase)
      browser = pw.chromium.launch(headless: !headful)
      context = browser.new_context(viewport: { width: 1280, height: 900 })
      page = context.new_page

      begin
        # 1. Load the calendar
        page.goto(TARGET_URL, timeout: 30_000, waitUntil: "domcontentloaded")
        page.wait_for_timeout(2_000)
        dismiss_newsletter_popup(page)

        # 2. Switch to List view
        list_link = page.locator('a[href*="list"], a:has-text("List")')
        assert list_link.count > 0, "Could not find a 'List' view link on the calendar page"
        list_link.first.click
        page.wait_for_load_state("networkidle", timeout: 15_000) rescue nil
        page.wait_for_timeout(3_000)

        assert page.url.include?("list") || page.locator(".tribe-events-list, .tribe-events-calendar-list").count > 0,
               "Failed to switch to list view (URL: #{page.url})"

        # --- Forward phase ---------------------------------------------------
        forward = [] # [{ url:, events: [...] }, ...]
        (FORWARD_STEPS + 1).times do |i|
          capture = { url: page.url, events: capture_list_events(page) }
          forward << capture
          puts "  ➡  [#{i}] #{capture[:events].size} events — #{capture[:url]}"

          if i < FORWARD_STEPS
            click_list_nav(page, :next)
          end
        end

        total_events = forward.sum { |p| p[:events].size }
        @failures << "No events captured in any of the #{forward.size} forward pages" if total_events == 0

        # Verify each forward step actually changed something
        forward.each_cons(2).with_index do |(prev_page, next_page), i|
          if prev_page[:url] == next_page[:url] && prev_page[:events] == next_page[:events]
            @failures << "Forward step #{i + 1}: page did not change (URL and events identical)"
          end
        end

        # --- Back phase ------------------------------------------------------
        FORWARD_STEPS.times do |i|
          click_list_nav(page, :previous)

          expected = forward[FORWARD_STEPS - 1 - i]
          actual = { url: page.url, events: capture_list_events(page) }
          puts "  ⬅  #{actual[:events].size} events — #{actual[:url]}"

          if actual[:events] != expected[:events]
            @failures << "Return step #{i + 1}: events differ — " \
                         "expected #{expected[:events].size} events, got #{actual[:events].size}"
          end
        end

        page.screenshot(path: ARTIFACT_DIR.join("nyk-list-nav-#{@stamp}.png").to_s, fullPage: true)

        if @failures.any?
          msg = "List view round-trip failed:\n  - " + @failures.join("\n  - ")
          puts "\n  ❌ #{msg}"
          flunk msg
        else
          puts "\n  ✅ NY Kitchen list nav: event sets survived a #{FORWARD_STEPS}-page round-trip."
        end
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

  def click_list_nav(page, direction)
    before_url = page.url
    before_events = capture_list_events(page)

    selector = if direction == :next
      'a.tribe-events-c-nav__next, a[rel="next"], .tribe-events-nav-next a, a:has-text("Next Events")'
    else
      'a.tribe-events-c-nav__prev, a[rel="prev"], .tribe-events-nav-previous a, a:has-text("Previous Events")'
    end

    link = page.locator(selector)
    assert link.count > 0, "Could not find '#{direction}' navigation link in list view"
    link.first.click

    # Wait for navigation — watch for URL or event change
    deadline = Time.now + 15
    while Time.now < deadline
      url_changed = page.url != before_url
      events_changed = capture_list_events(page) != before_events
      break if url_changed || events_changed
      page.wait_for_timeout(250)
    end
    page.wait_for_load_state("networkidle", timeout: 5_000) rescue nil
    page.wait_for_timeout(1_000)
  end

  def capture_list_events(page)
    page.evaluate(<<~JS) || []
      Array.from(
        document.querySelectorAll(
          '.tribe-events-list-event-title, ' +
          '.tribe-events-calendar-list__event-title, ' +
          '.tribe-common-h6, ' +
          'h2.tribe-events-list-event-title'
        )
      ).map(el => el.textContent.trim().replace(/\\s+/g, ' '))
    JS
  end

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
end
