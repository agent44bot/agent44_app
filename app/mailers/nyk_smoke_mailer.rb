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
      subject: "🚨 NY Kitchen smoke failed — #{@started_at.strftime("%-I:%M %p %Z")}"
    )
  end
end
