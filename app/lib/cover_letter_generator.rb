# On-demand, job-specific cover letter for Rich, grounded in his résumé summary
# (config/job_match_profile.yml → application.resume_summary). Generated only when
# he opens a match's apply kit, stored on the JobMatch so it persists. Uses Sonnet
# (this is a high-stakes, applicant-facing artifact), logged via AiCallLogger, and
# degrades to nil on any error. Em dashes are stripped by JobMatch on save.
module CoverLetterGenerator
  module_function

  MODEL = "claude-sonnet-4-6".freeze

  def generate!(match)
    job = match.job
    api_key = Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"]
    return nil if api_key.blank?

    resp = Anthropic::Client.new(api_key: api_key).messages.create(
      model: MODEL, max_tokens: 800,
      messages: [ { role: "user", content: prompt_for(job) } ]
    )
    AiCallLogger.log!(resp, model: MODEL, source: "cover_letter")

    text = resp.content.filter_map { |b| b.respond_to?(:text) ? b.text : b["text"] }.join.strip
    match.update!(cover_letter: text.presence, cover_letter_at: Time.current)
    match.cover_letter
  rescue => e
    Rails.logger.warn("CoverLetterGenerator failed for job #{match.job_id}: #{e.class}: #{e.message}")
    nil
  end

  def prompt_for(job)
    app = JobMatcher.profile["application"] || {}
    <<~TXT
      Write a cover letter for Rich Downie applying to the job below. Rules:
      - Ground it ONLY in his real background; never invent experience or claim
        skills he lacks. If the role leans on a gap, briefly frame how he'd ramp.
      - 200-260 words, 3 short paragraphs, first person, confident but not boastful.
      - Lead with the single strongest, most specific reason he fits THIS role.
      - Plain modern language. Use commas and periods. Do NOT use em dashes or en
        dashes (— or –) anywhere.
      - Output ONLY the body paragraphs. No "Dear Hiring Manager" line, no
        signature block, no placeholders in brackets.

      Candidate: #{app['resume_summary']}
      Work arrangement: #{app['arrangement']}.

      Job: #{job.title} at #{job.company} (#{job.location}).
      #{job.description.to_s[0, 1800]}
    TXT
  end
end
