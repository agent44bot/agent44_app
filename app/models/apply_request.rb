class ApplyRequest < ApplicationRecord
  # Lifecycle of an assisted application. The Mac-Mini Playwright runner (Phase
  # 2) consumes "queued" rows, opens the posting, fills what it can, and stops
  # at the submit button ("filled"). Rich marks "applied" himself after he
  # clicks submit. Nothing is ever auto-submitted.
  STATUSES = %w[queued opened filled applied skipped error].freeze

  belongs_to :job

  validates :status, inclusion: { in: STATUSES }

  scope :queued,  -> { where(status: "queued") }
  scope :pending, -> { where(status: %w[queued opened filled]) }
  scope :recent,  -> { order(updated_at: :desc) }

  # Enqueue (or re-enqueue) an application for a job. Idempotent: one row per
  # job, reset to queued so the runner picks it up again.
  def self.enqueue!(job)
    req = find_or_initialize_by(job_id: job.id)
    req.update!(status: "queued", requested_at: Time.current, notes: nil)
    req
  end

  def status_label
    { "queued" => "Queued", "opened" => "Opening", "filled" => "Ready to submit",
      "applied" => "Applied", "skipped" => "Skipped", "error" => "Needs attention" }[status] || status
  end
end
