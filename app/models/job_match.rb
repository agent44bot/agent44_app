class JobMatch < ApplicationRecord
  belongs_to :job

  scope :ranked,   -> { order(score: :desc, id: :desc) }
  scope :enriched, -> { where.not(enriched_at: nil) }
  scope :dreams,   -> { where(is_dream: true) }

  before_save :normalize_ai_dashes

  # Em/en dashes (— –) are a dead giveaway that prose is AI-written. Rich pastes
  # these pitches straight into applications, so swap them for commas. Regular
  # hyphens (full-stack, CI/CD, 25-year) are left alone.
  def self.strip_dashes(str)
    return str if str.blank?
    str.to_s.gsub(/\s*[—–]\s*/, ", ").gsub(/,\s*,/, ",").gsub(/\s{2,}/, " ").strip
  end

  # Upsert the rule-based score for a job from a JobMatcher.evaluate result.
  # Leaves the AI enrichment columns (why/pitch/lead_skills/enriched_at) alone
  # so a nightly re-score never costs a re-enrichment.
  def self.record!(job, result)
    m = find_or_initialize_by(job_id: job.id)
    m.score          = result[:score]
    m.matched_skills = result[:matched_skills]
    m.is_dream       = result[:is_dream]
    m.reasons        = result[:reasons]
    m.computed_at    = Time.current
    m.save!
    m
  end

  def enriched? = enriched_at.present?

  private

  # Runs on every save (incl. enrichment's update!), so any AI-written field is
  # de-em-dashed before it reaches the For You page or the digest email.
  def normalize_ai_dashes
    self.why   = self.class.strip_dashes(why)   if why.present?
    self.pitch = self.class.strip_dashes(pitch) if pitch.present?
    self.lead_skills = Array(lead_skills).map { |s| self.class.strip_dashes(s) } if lead_skills.present?
  end
end
