require_relative "nyk_smoke_base"

# Scrapes NY Kitchen event detail pages and posts a daily snapshot to
# /api/v1/kitchen_snapshots so KitchenDigestEmailJob (10am ET) can email
# Lora the difference vs. yesterday.
#
# This test deliberately uses the "click This Month first" workaround for
# the TEC live_refresh arrow-nav bug — its job is data freshness, not bug
# detection. The arrow-nav regression is covered by nyk_calendar_nav_test.rb
# on its own schedule.
#
#   1. Load /calendar/
#   2. Click "This Month" (stabilizes TEC live_refresh state)
#   3. Walk forward N months via arrows, collecting event URLs at each
#   4. Visit each unique upcoming event URL, scrape detail
#   5. POST snapshot to /api/v1/kitchen_snapshots
#
# Run with:  RUN_SMOKE=true bin/rails test test/smoke/nyk_scrape_test.rb
class NykScrapeTest < NykSmokeBase
  TEST_NAME = BROWSER == "chromium" ? "nyk_scrape" : "nyk_scrape_#{BROWSER}"
  ARTIFACT_PREFIX = "nyk-scrape"
  FORWARD_STEPS = 3 # arrow-clicks past initial load; total months scraped = 4

  test "scrape: walk forward N months via 'This Month' workaround, scrape events, post snapshot" do
    Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
      headful = %w[1 true yes t y].include?(ENV["HEADFUL"].to_s.downcase)
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

        # --- Workaround: click "This Month" to settle TEC live_refresh state ---
        clicked = click_this_month(page)
        if clicked
          progress_ping("🤖 Vlad — NYK scrape: applied This Month workaround", body: "starting #{FORWARD_STEPS + 1}-month forward walk")
        else
          puts "  ⚠  'This Month' button not found — proceeding without workaround"
          record_step(kind: "this_month_workaround", note: "button not found, skipped")
        end
        page.wait_for_timeout(STEP_PAUSE_MS)

        # --- Forward phase: collect event URLs from each month ---
        all_event_urls = []
        forward = []
        (FORWARD_STEPS + 1).times do |i|
          title = read_month_title(page)
          events = capture_events(page)
          forward << { title: title, events: events }
          all_event_urls.concat(collect_event_urls(page))
          record_step(kind: "month_view", direction: "forward", title: title, events: events.size)
          puts "  ➡  [#{i}] #{title} — #{events.size} events"

          if i < FORWARD_STEPS
            click_nav(page, "next")
            page.wait_for_timeout(STEP_PAUSE_MS)
          end
        end

        total_events = forward.sum { |m| m[:events].size }
        if total_events == 0
          fail_with_artifacts(page, context, "No events captured in any of the #{forward.size} forward months — calendar not loading. The 'This Month' workaround did not help.")
          return
        end

        # --- Scrape phase: visit each upcoming event detail page ---
        today = Date.today
        unique_urls = all_event_urls.uniq.reject { |url|
          if url =~ /(\d{1,2})-(\d{1,2})-(\d{2,4})\/?$/
            m, d, y = $1.to_i, $2.to_i, $3.to_i
            y += 2000 if y < 100
            Date.new(y, m, d) < today rescue false
          else
            false
          end
        }

        puts "\n  🔍 Scraping #{unique_urls.size} event detail pages (skipped past dates)..."
        progress_ping("🤖 Vlad — Scraping #{unique_urls.size} event pages", body: "forward walk OK, gathering details")

        scraped_events = []
        last_pct = -1
        unique_urls.each_with_index do |url, i|
          begin
            event = scrape_detail_page(page, url)
            if event
              scraped_events << event
              puts "    [#{i + 1}/#{unique_urls.size}] #{event[:name]&.to_s&.truncate(50) || url}"
            else
              puts "    [#{i + 1}/#{unique_urls.size}] SKIPPED (404/deleted): #{url}"
            end
          rescue => e
            puts "    [#{i + 1}/#{unique_urls.size}] FAILED: #{e.message}"
          end
          pct = ((i + 1) * 100 / unique_urls.size / 10) * 10
          if pct > last_pct
            update_vlad_status("busy", "Scraping nykitchen #{pct}%")
            last_pct = pct
          end
          page.wait_for_timeout(DETAIL_PAGE_PAUSE_MS) if i < unique_urls.size - 1
        end

        # Filter out past events — only future classes go in the snapshot.
        before = scraped_events.size
        today_str = today.to_s
        scraped_events.reject! { |e|
          e[:passed] ||
          (e[:start_at].present? && e[:start_at].to_s < today_str)
        }
        skipped = before - scraped_events.size
        puts "    Filtered: #{skipped} past event(s) removed, #{scraped_events.size} upcoming kept" if skipped > 0

        post_kitchen_snapshot(scraped_events) if scraped_events.any?

        context.tracing.stop
        context.close
        browser.close

        summary = "#{forward.map { |m| m[:events].size }.join("/")} events seen, #{scraped_events.size} scraped & snapshotted"
        run_id = post_result(status: "passed", summary: summary)
        upload_video(run_id) if run_id
        progress_ping("✅ Vlad — NYK scrape PASSED", body: summary, level: "success")
        assert scraped_events.any?, "Scrape collected zero events — snapshot would be empty"
      rescue => e
        fail_with_artifacts(page, context, "#{e.class}: #{e.message}")
      ensure
        browser&.close rescue nil
      end
    end
  end

  private

  # The "This Month" / "Today" button on TEC's calendar top bar. Clicking it
  # forces TEC to re-render the current month and resets the live_refresh
  # internal state, which avoids the empty-grid bug that affects raw arrow
  # navigation.
  #
  # Selectors fall through known TEC variants — if TEC ever renames the
  # button class, the text-based fallback should still match.
  def click_this_month(page)
    candidates = [
      ".tribe-events-c-top-bar__today-button",
      '[data-js="tribe-events-view-link"][data-link*="today"]',
      "button.tribe-events-c-top-bar__today-button",
      "a.tribe-events-c-top-bar__today-button"
    ]

    candidates.each do |selector|
      begin
        locator = page.locator(selector).first
        if locator.count > 0
          puts "  🎯 Clicking '#{selector}' (This Month workaround)"
          locator.click
          record_step(kind: "this_month_workaround", selector: selector)
          page.wait_for_timeout(NAV_WAIT_MS)
          page.wait_for_load_state("networkidle", timeout: 5_000) rescue nil
          return true
        end
      rescue => e
        puts "  ⚠  '#{selector}' click error: #{e.class}: #{e.message}"
      end
    end

    # Last-resort: text-based match
    %w[This\ Month Today].each do |text|
      begin
        locator = page.get_by_role("button", name: text, exact: false).first
        if locator.count > 0
          puts "  🎯 Clicking text='#{text}' (This Month workaround, fallback)"
          locator.click
          record_step(kind: "this_month_workaround", text: text)
          page.wait_for_timeout(NAV_WAIT_MS)
          return true
        end
      rescue
        next
      end
    end

    false
  end
end
