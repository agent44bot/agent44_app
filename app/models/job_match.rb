class JobMatch < ApplicationRecord
  belongs_to :job

  scope :ranked,   -> { order(score: :desc, id: :desc) }
  scope :enriched, -> { where.not(enriched_at: nil) }
  scope :dreams,   -> { where(is_dream: true) }

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
end
