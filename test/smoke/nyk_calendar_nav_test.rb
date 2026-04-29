require_relative "nyk_smoke_base"

# Black-box regression check for https://nykitchen.com/calendar/.
#
# What this test exists to catch: clicking the < / > month-nav arrows
# leaving the calendar grid empty (a TEC live_refresh handler bug). Workaround
# is to use the month dropdown / "This Month" button, which is what the
# scraper test uses to keep Lora's data flowing — but that workaround masks
# the underlying bug. This test deliberately exercises the user-facing arrow
# path so the bug regresses loudly.
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
# Event signature = WP post ID. Title kept alongside for readable error messages.
#
# Run with:  RUN_SMOKE=true bin/rails test test/smoke/nyk_calendar_nav_test.rb
# Watch it:  HEADFUL=true rake test:smoke:nyk
#
# This test does NOT scrape event detail pages or update kitchen snapshots —
# that lives in nyk_scrape_test.rb so a nav-arrow failure here does not
# block Lora's daily digest.
class NykCalendarNavTest < NykSmokeBase
  TEST_NAME = BROWSER == "chromium" ? "nyk_calendar_nav" : "nyk_calendar_nav_#{BROWSER}"
  ARTIFACT_PREFIX = "nyk-calendar-nav"
  FORWARD_STEPS = 3 # clicks past initial load; total months visited = 4

  test "events round-trip: nav forward N months, back N months, event sets match" do
    # Escape hatch for wiring/testing the failure email path — forces a fake
    # failure after capturing a real video so we can verify end-to-end delivery.
    if ENV["FORCE_FAIL"] == "true"
      Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
        browser = pw.public_send(BROWSER).launch(headless: true)
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
      # Default to headed: lower bot fingerprint (less detectable than headless
      # Chromium) matters since this test runs hourly. Set HEADFUL=false to
      # force headless (e.g. on a runner without a display).
      headful = ENV["HEADFUL"].to_s.downcase != "false"
      browser = pw.public_send(BROWSER).launch(headless: !headful)
      puts "  🌐 Driving #{BROWSER} (test name: #{TEST_NAME})#{headful ? " [headful]" : ""}"
      context = browser.new_context(
        viewport: { width: 1280, height: 900 },
        record_video_dir: @video_dir.to_s
      )
      context.tracing.start(screenshots: true, snapshots: true, sources: false)
      page = context.new_page
      attach_console_listeners(page)

      begin
        page.goto(TARGET_URL, timeout: 30_000, waitUntil: "domcontentloaded")
        record_step(kind: "load", url: TARGET_URL)
        page.wait_for_selector(event_selector, timeout: 15_000)
        dismiss_newsletter_popup(page) unless ENV["NO_POPUP_KILL"] == "true"
        record_step(kind: "popup_dismissed") unless ENV["NO_POPUP_KILL"] == "true"
        page.wait_for_timeout(STEP_PAUSE_MS)
        progress_ping("🤖 Vlad — Loaded NYK calendar", body: "starting #{FORWARD_STEPS + 1}-month round-trip")

        # --- Forward phase -------------------------------------------------
        forward = []
        (FORWARD_STEPS + 1).times do |i|
          capture = { title: read_month_title(page), events: capture_events(page) }
          forward << capture
          record_step(kind: "month_view", direction: "forward", title: capture[:title], events: capture[:events].size)
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
          record_step(kind: "month_view", direction: "back", title: actual[:title], events: actual[:events].size, expected_events: expected[:events].size)
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
          context.tracing.stop
          context.close
          browser.close
          summary = forward.map { |m| m[:events].size }.join("/") + " events round-tripped"
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
end
