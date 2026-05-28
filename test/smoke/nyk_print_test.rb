require_relative "nyk_smoke_base"

# Argus's print check. Loads BOTH live printouts and verifies each collates:
#   - the double-sided flyer  (/nykitchen/display/print)         — up to 18, 9/side
#   - the stall poster        (…?variant=stall)                  — up to 6, one page
# For each: at least one upcoming class, a QR per class, and every photo loads
# and isn't the building-default fallback (the GTP_NYK-OUTDOORS bug that put the
# wrong photo on the flyer).
#
# Complements the deterministic collation coverage in display_print_test.rb by
# checking the real, deployed pages + real image loads. Posts to
# /api/v1/smoke_runs as "nyk_print" so it shows in the Test agent's stats.
#
#   RUN_SMOKE=true bin/rails test test/smoke/nyk_print_test.rb
#   (watch it: HEADFUL=true SLOWMO=1200 …)
class NykPrintTest < NykSmokeBase
  TEST_NAME = BROWSER == "chromium" ? "nyk_print" : "nyk_print_#{BROWSER}"
  ARTIFACT_PREFIX = "nyk-print"
  PRINT_URL = "#{API_URL}/nykitchen/display/print"

  test "flyer (18, 9/side) and stall poster (6) collate with QR codes and real photos" do
    Playwright.create(playwright_cli_executable_path: playwright_cli) do |pw|
      headful = %w[1 true yes t y].include?(ENV["HEADFUL"].to_s.downcase)
      browser = pw.public_send(BROWSER).launch(headless: !headful, slowMo: ENV["SLOWMO"].to_i)
      context = browser.new_context(
        viewport: { width: 1280, height: 1600 },
        record_video_dir: @video_dir.to_s
      )
      context.tracing.start(screenshots: true, snapshots: true, sources: false)
      page = context.new_page
      attach_console_listeners(page)

      begin
        flyer = inspect_variant(page, context, PRINT_URL,                      label: "flyer",        max: 18, per_page: 9)
        stall = inspect_variant(page, context, "#{PRINT_URL}?variant=stall",   label: "stall poster", max: 6,  per_page: nil)

        context.tracing.stop
        context.close
        browser.close

        summary = "flyer #{flyer[:events]}/#{flyer[:pages]}p, stall #{stall[:events]} · " \
                  "#{flyer[:imgs] + stall[:imgs]} photos, #{flyer[:qrs] + stall[:qrs]} QR — all OK"
        run_id = post_result(status: "passed", summary: summary)
        upload_video(run_id) if run_id
        progress_ping("✅ Vlad — NYK print PASSED", body: summary, level: "success")
        puts "  ✅ #{summary}"

        assert flyer[:events].positive?, "flyer should list at least one class"
        assert stall[:events].positive?, "stall poster should list at least one class"
      rescue => e
        fail_with_artifacts(page, context, "#{e.class}: #{e.message}")
      ensure
        browser&.close rescue nil
      end
    end
  end

  private

  # Load one print variant, validate its collation + photos, return its counts.
  # Calls fail_with_artifacts (which flunks) on any problem.
  def inspect_variant(page, context, url, label:, max:, per_page:)
    puts "  🌐 #{label} → #{url}"
    res = page.goto(url, timeout: 30_000, waitUntil: "networkidle")
    status = (res&.status rescue 0).to_i
    fail_with_artifacts(page, context, "#{label} returned HTTP #{status}") if status >= 400

    page.wait_for_selector(".event", timeout: 15_000)
    page.wait_for_timeout(1_500) # let cross-origin photos settle before checking

    d = page.evaluate(<<~JS)
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
    problems << "no classes shown"                                                          if d["events"].to_i.zero?
    problems << "#{d['events']} classes (cap is #{max})"                                     if d["events"].to_i > max
    problems << "#{d['broken']} photo(s) failed to load"                                     if d["broken"].to_i.positive?
    problems << "#{d['building']} building-default photo(s) (GTP_NYK-OUTDOORS)"              if d["building"].to_i.positive?
    problems << "#{d['qrs']} QR codes for #{d['events']} classes"                            if d["qrs"].to_i != d["events"].to_i
    expected_pages = per_page ? (d["events"].to_i / per_page.to_f).ceil : 1
    problems << "#{d['pages']} page(s), expected #{expected_pages}"                          if d["pages"].to_i != expected_pages
    fail_with_artifacts(page, context, "#{label} issues: #{problems.join('; ')}") if problems.any?

    puts "  ✅ #{label}: #{d['events']} classes / #{d['pages']} page(s) · #{d['qrs']} QR · #{d['imgs']} photos"
    d.transform_keys(&:to_sym)
  end
end
