class NykSmokeMailer < ApplicationMailer
  TARGET_URL = "https://nykitchen.com/calendar/"
  TESTS_TAB_URL = "https://agent44labs.com/nykitchen?tab=tests"

  def failure(failure_message:, started_at:, recipients:,
              console_errors: nil, steps: nil,
              calendar_url_at_failure: nil,
              user_agent: nil, runner_name: nil,
              run_id: nil,
              page_source_url: nil, trace_url: nil)
    @failure_message = failure_message.to_s
    @console_errors  = Array(console_errors).reject(&:blank?)
    @network_errors  = @console_errors.select { |line| line.start_with?("[requestfailed]") || line.match?(/\A\[response \d{3}\]/) }
    @likely_causes   = build_likely_causes(@network_errors, @failure_message)
    @started_at      = started_at
    @target_url      = TARGET_URL
    @steps           = Array(steps)
    @calendar_url_at_failure = calendar_url_at_failure.presence
    @user_agent      = user_agent.to_s
    @runner_name     = runner_name.presence || "unknown runner"
    @run_id          = run_id
    @page_source_url = page_source_url.presence
    @trace_url       = trace_url.presence
    @tests_tab_url   = if run_id
      "#{TESTS_TAB_URL}#smoke_test_run_#{run_id}"
    else
      TESTS_TAB_URL
    end

    mail(
      to: recipients,
      subject: "🚨 NY Kitchen test failed — #{@started_at.strftime("%-I:%M %p %Z")}"
    )
  end

  private

  # Three theories ranked by how often we've seen each one. Auto-flag whichever
  # theory the signals from this run match so the developer's eye lands there
  # first.
  def build_likely_causes(network_errors, failure_message)
    rest_endpoint_signals = network_errors.any? do |e|
      e.include?("wp-json/tribe/views") ||
        e.include?("admin-ajax.php") ||
        e.include?("tribe_calendar")
    end

    [
      {
        title: "WordPress REST endpoint flaking",
        matched: rest_endpoint_signals,
        body: "When the user clicks Next, The Events Calendar fires a POST to <code>/wp-json/tribe/views/v2/html</code>. If that endpoint times out or returns 5xx, TEC updates the month title locally but the grid never repopulates — exactly the empty-grid symptom this test catches.",
        check: "Server logs for <code>/wp-json/</code> errors at the failure timestamp. SiteGround is known to rate-limit <code>/wp-json/</code> under burst traffic — check the host's WAF and rate-limit rules.",
        match_label: "Network failures against this endpoint were captured in this run."
      },
      {
        title: "Click race — TEC JS not bound when the click fires",
        matched: false,
        body: "The Next button is <code>data-js=\"tribe-events-view-link\"</code>; TEC binds its click handler at runtime. If a click fires before the handler is bound, the browser may follow the underlying anchor (full reload) or do nothing, leaving the AJAX path unused.",
        check: "Confirm <code>tribe-events-view.min.js</code> loads and binds before any <code>data-js=\"tribe-events-view-link\"</code> in the DOM. Look for JS errors earlier in the page that could prevent binding.",
        match_label: nil
      },
      {
        title: "Concurrent state collision (live_refresh: true)",
        matched: false,
        body: "Calendar config has <code>live_refresh: true</code>. If a separate script triggers a TEC view refresh while a navigation is in flight, TEC's in-flight guard has historically dropped one of the responses.",
        check: "Disable <code>live_refresh</code> temporarily and see if the symptom disappears. Audit other scripts on <code>/calendar/</code> that may be calling TEC's view API.",
        match_label: nil
      }
    ]
  end
end
