require_relative "nyk_smoke_base"

# Argus's print check. Loads the LIVE printable flyer (/nykitchen/display/print)
# in a browser and verifies it collates properly:
#   - lists at least one upcoming class, paginated 9-per-side
#   - a QR code per class
#   - every photo actually loads (not broken) and none is the building-default
#     fallback (the GTP_NYK-OUTDOORS bug that put the wrong photo on the flyer)
#
# Complements the deterministic collation coverage in display_print_test.rb by
# checking the real, deployed page + real image loads — things a server-render
# test can't see. Posts to /api/v1/smoke_runs as "nyk_print" so it shows in the
# Test agent's stats and the weekly team report.
#
#   RUN_SMOKE=true bin/rails test test/smoke/nyk_print_test.rb
class NykPrintTest < NykSmokeBase
  TEST_NAME = BROWSER == "chromium" ? "nyk_print" : "nyk_print_#{BROWSER}"
  ARTIFACT_PREFIX = "nyk-print"
  PRINT_URL = "#{API_URL}/nykitchen/display/print"

  test "print flyer collates upcoming classes with QR codes and real photos" do
    Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
      headful = %w[1 true yes t y].include?(ENV["HEADFUL"].to_s.downcase)
      browser = pw.public_send(BROWSER).launch(headless: !headful)
      puts "  🌐 Driving #{BROWSER} → #{PRINT_URL}"
      context = browser.new_context(
        viewport: { width: 1280, height: 1600 },
        record_video_dir: @video_dir.to_s
      )
      context.tracing.start(screenshots: true, snapshots: true, sources: false)
      page = context.new_page
      attach_console_listeners(page)

      begin
        res = page.goto(PRINT_URL, timeout: 30_000, waitUntil: "networkidle")
        status = (res&.status rescue 0).to_i
        if status >= 400
          fail_with_artifacts(page, context, "Print page returned HTTP #{status}")
          return
        end

        page.wait_for_selector(".event", timeout: 15_000)
        page.wait_for_timeout(1_500) # let cross-origin photos settle before checking

        data = page.evaluate(<<~JS)
          (() => {
            const events = Array.from(document.querySelectorAll('.event'));
            const imgs   = Array.from(document.querySelectorAll('img.thumb'));
            return {
              events:   events.length,
              pages:    document.querySelectorAll('.page').length,
              qrs:      document.querySelectorAll('.qr svg').length,
              imgs:     imgs.length,
              broken:   imgs.filter(i => !i.complete || i.naturalWidth === 0).length,
              building: imgs.filter(i => (i.currentSrc || i.src || '').includes('GTP_NYK-OUTDOORS')).length
            };
          })()
        JS

        problems = []
        problems << "no classes on the flyer"                                                          if data["events"].to_i.zero?
        problems << "#{data['broken']} photo(s) failed to load"                                        if data["broken"].to_i.positive?
        problems << "#{data['building']} class(es) show the building-default photo (GTP_NYK-OUTDOORS)" if data["building"].to_i.positive?
        problems << "#{data['qrs']} QR codes for #{data['events']} classes"                            if data["qrs"].to_i != data["events"].to_i
        expected_pages = (data["events"].to_i / 9.0).ceil
        problems << "expected #{expected_pages} page(s) for #{data['events']} classes, saw #{data['pages']}" if data["pages"].to_i != expected_pages

        if problems.any?
          fail_with_artifacts(page, context, "Print flyer issues: #{problems.join('; ')}")
          return
        end

        context.tracing.stop
        context.close
        browser.close

        summary = "#{data['events']} classes / #{data['pages']} page(s) · #{data['qrs']} QR · #{data['imgs']} photos all OK"
        run_id = post_result(status: "passed", summary: summary)
        upload_video(run_id) if run_id
        progress_ping("✅ Vlad — NYK print PASSED", body: summary, level: "success")
        puts "  ✅ #{summary}"

        assert data["events"].to_i.positive?, "flyer should list at least one class"
        assert_equal 0, data["broken"].to_i,   "no broken photos"
        assert_equal 0, data["building"].to_i, "no building-default photos"
      rescue => e
        fail_with_artifacts(page, context, "#{e.class}: #{e.message}")
      ensure
        browser&.close rescue nil
      end
    end
  end
end
