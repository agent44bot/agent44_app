# Claude-generated "why it fits / skills to lead with / opening pitch" for a top
# JobMatch, given Rich's profile. Cheap (haiku), logged via AiCallLogger, and
# degrades to a no-op on any error so ranking never depends on the API.
module JobMatchEnricher
  module_function

  MODEL = "claude-haiku-4-5".freeze

  def enrich!(match)
    job = match.job
    api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
    return false if api_key.blank?

    resp = Anthropic::Client.new(api_key: api_key).messages.create(
      model: MODEL, max_tokens: 450,
      messages: [ { role: "user", content: prompt_for(job) } ]
    )
    AiCallLogger.log!(resp, model: MODEL, source: "job_match")

    text = resp.content.filter_map { |b| b.respond_to?(:text) ? b.text : b["text"] }.join
    data = JSON.parse(text[/\{.*\}/m] || "{}")

    match.update!(
      why:         data["why_fit"].to_s.strip.presence,
      lead_skills: Array(data["lead_skills"]).map(&:to_s).reject(&:blank?).first(5),
      pitch:       data["pitch"].to_s.strip.presence,
      enriched_at: Time.current
    )
    true
  rescue => e
    Rails.logger.warn("JobMatchEnricher failed for job #{match.job_id}: #{e.class}: #{e.message}")
    false
  end

  def prompt_for(job)
    <<~TXT
      You are a career coach for Rich Downie, a Rochester NY "Automation Architect"
      with 25+ years in test automation / SDET who is pivoting into AI agent
      engineering. He has shipped real agentic systems: Claude API / Anthropic SDK,
      MCP servers, OpenClaw automation, and a multi-agent fleet. Core stack:
      Ruby/Rails, Playwright, Selenium/Appium, TypeScript, Python, GitHub Actions,
      AWS, Fly.io, Docker, Postgres. Honest gaps: Java, C#/.NET, Kotlin/Swift,
      Kubernetes. He prefers remote, is open to part-time/contract to ease the
      transition, and would take full-time for the right role.

      Evaluate the job below for Rich. Be specific and honest — if it leans on his
      gaps, say how he'd bridge them. Write plainly: use commas and periods, and
      do NOT use em dashes or en dashes (— or –) anywhere. Respond with ONLY a
      JSON object, no prose:
      {"why_fit": "1-2 sentences on why this role fits Rich specifically",
       "lead_skills": ["3-5 of Rich's skills/experiences to emphasize for THIS role"],
       "pitch": "2-3 sentence first-person opening line Rich can paste into an application"}

      Job: #{job.title} at #{job.company} (#{job.location}).
      #{job.description.to_s[0, 1500]}
    TXT
  end
end
