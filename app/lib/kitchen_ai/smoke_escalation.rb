# frozen_string_literal: true

# When the NYK calendar smoke test (nav) fails several runs in a row, this is
# the shared brain for the escalation: the threshold, the trial audience, the
# draft-email prompt, and the auto-ask deep link. Used by both the hub card
# (passive) and SmokeTestFailureNotificationJob (active iOS push).
#
# v1 is draft-only and triage-first: the prompt asks the Super Agent to read the
# failures, judge whether it's a real site problem, and only then draft an email
# to the developer for the user to send. Nothing is sent automatically.
module KitchenAi
  module SmokeEscalation
    THRESHOLD = 3 # consecutive failed nav runs before we escalate

    module_function

    def streak       = SmokeTestRun.nyk_nav_failure_streak
    def alerting?(n = streak) = n >= THRESHOLD
    def started_at   = SmokeTestRun.nyk_nav_streak_started_at

    # The trial recipient — reuses the morning-prompt gate so the dogfood
    # audience is one knob (RB now → Lora later). Blank setting = nobody.
    def trial_user
      email = Setting.get("super_agent_daily_prompt_email").to_s.strip.downcase
      return nil if email.blank?
      User.find_by("LOWER(email_address) = ?", email)
    end

    # The question we drop into /nykitchen/ask. Triage-first, draft-only.
    def draft_prompt(n = streak)
      dev       = Setting.get("nyk_developer_email").to_s.strip.presence
      recipient = dev ? "the developer (#{dev})" : "the developer"
      since     = started_at&.in_time_zone("Eastern Time (US & Canada)")&.strftime("%a %b %-d %-l:%M%P")
      "The class calendar smoke test has failed #{n} times in a row" \
        "#{since ? " since #{since}" : ""}. Look at the recent failures, decide whether it's a " \
        "real problem with the booking site (not just a flaky test run), and if it looks real, " \
        "draft an email to #{recipient} describing what's broken and when it started. " \
        "Do not send it — just draft it for me to review."
    end

    # Incident key for de-duping the active push: one alert per streak, no matter
    # how many more runs fail or how often the job retries.
    def incident_key = started_at&.iso8601
  end
end
