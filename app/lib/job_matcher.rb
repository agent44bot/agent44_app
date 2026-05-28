# Scores a Job against Rich's profile (config/job_match_profile.yml) for the
# personalized For You feed + daily digest. Pure, deterministic rule scoring;
# the AI "why it fits / how to pitch" layer lives in JobMatchEnricher.
#
# Score is 0–100, additive:
#   role_class weight (≤40) + skill overlap (≤35) + seniority (10) + remote (8)
#   + recency (≤5) + dream bonus (5), minus a gap penalty (≤15).
module JobMatcher
  module_function

  PROFILE_PATH = "config/job_match_profile.yml".freeze
  MAX_SKILL_HITS = 8

  def profile
    @profile ||= YAML.load_file(Rails.root.join(PROFILE_PATH))
  end

  def reload_profile!
    @profile = nil
    @skill_regex = nil
  end

  # Returns { score:, matched_skills:, is_dream:, reasons: {} } for a Job.
  def evaluate(job)
    text  = "#{job.title} #{job.description}".downcase
    title = job.title.to_s.downcase

    weights = profile["role_class_weights"]
    base = (weights[job.role_class] || weights["traditional"]).to_i

    matched   = profile["skills"].select { |s| text.match?(skill_regex(s)) }.uniq
    skill_pts = ([ matched.size, MAX_SKILL_HITS ].min / MAX_SKILL_HITS.to_f * 35)

    seniority     = profile["seniority_keywords"].any? { |k| text.match?(skill_regex(k)) }
    seniority_pts = seniority ? 10 : 0

    remote     = remote?(job)
    remote_pts = remote ? 8 : 0

    is_dream  = profile["dream_keywords"].any? { |k| text.include?(k) }
    dream_pts = is_dream ? 5 : 0

    days        = ((Time.current - (job.posted_at || job.created_at)) / 1.day).to_i
    recency_pts = days <= 3 ? 5 : days <= 7 ? 4 : days <= 14 ? 2 : 0

    # A gap skill in the TITLE means it's likely core to the role (heavy penalty);
    # repeated mentions in the body are a softer signal.
    gap_in_title = profile["gap_keywords"].any? { |g| title.match?(skill_regex(g)) }
    gap_in_body  = profile["gap_keywords"].any? { |g| text.scan(skill_regex(g)).size >= 2 }
    gap_penalty  = gap_in_title ? 15 : (gap_in_body ? 8 : 0)

    # Salary floor: dock listings whose explicit annual salary is below his
    # current comp (graduated by how far below, capped). No posted salary or
    # hourly/contract rates parse to nil → neutral (parse_salary_midpoint skips them).
    floor      = profile["salary_floor"].to_i
    salary     = floor.positive? ? Job.parse_salary_midpoint(job.salary) : nil
    below_floor = salary.present? && salary < floor
    salary_penalty = below_floor ? [ ((floor - salary).to_f / floor * 30).round, 20 ].min : 0

    score = (base + skill_pts + seniority_pts + remote_pts + dream_pts + recency_pts - gap_penalty - salary_penalty).round.clamp(0, 100)

    {
      score: score,
      matched_skills: matched,
      is_dream: is_dream,
      reasons: {
        role_class: job.role_class, base: base, skill_pts: skill_pts.round,
        seniority: seniority, remote: remote, dream: is_dream,
        recency_days: days, gap_penalty: gap_penalty,
        salary: salary, below_floor: below_floor, salary_penalty: salary_penalty
      }
    }
  end

  # Word-boundary-ish match that tolerates tokens with . / # + (c#, ci/cd, fly.io).
  def skill_regex(token)
    @skill_regex ||= {}
    @skill_regex[token] ||= /(?<![a-z0-9])#{Regexp.escape(token)}(?![a-z0-9])/i
  end

  def remote?(job)
    "#{job.location} #{job.title}".match?(/remote|anywhere|distributed/i)
  end
end
