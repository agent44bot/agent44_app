# Feedback a signed-in user sends from the Feedback button (message plus
# optional screenshots or files). Rich is pushed on submit and gets an email
# copy; the sender gets an acknowledgement, and another email when Rich marks
# it shipped. See FeedbackSubmittedJob / FeedbackMailer.
class Feedback < ApplicationRecord
  belongs_to :user
  belongs_to :workspace, optional: true
  has_many_attached :attachments

  # The pipeline (docs/feedback_pipeline.md). "in_progress" is the phase 1
  # manual status, kept valid for items moved by hand.
  STATUSES = %w[received planned needs_info approved changes_requested pr_ready
                merge_requested in_progress shipped closed].freeze
  # What Rich sees in the admin inbox.
  LABELS = {
    "received" => "Received", "planned" => "Plan ready", "needs_info" => "Asked sender",
    "approved" => "Building", "changes_requested" => "Changes requested",
    "pr_ready" => "Ready to merge", "merge_requested" => "Merging",
    "in_progress" => "In progress", "shipped" => "Live", "closed" => "Closed"
  }.freeze
  # What the sender sees: the pipeline stays behind the curtain.
  SENDER_LABELS = { "received" => "Received", "needs_info" => "Question for you",
                    "shipped" => "Live", "closed" => "Closed" }.freeze
  DONE = %w[shipped closed].freeze
  # Statuses where the mini has work to do, and what that work is.
  AGENT_STEPS = { "received" => "plan", "approved" => "build",
                  "changes_requested" => "build", "merge_requested" => "merge" }.freeze
  # A claim older than this is treated as a crashed worker, and the item is
  # handed out again.
  CLAIM_TTL = 45.minutes

  # The board's columns, in order (Rich, 2026-09-22). Each status lands in
  # exactly one; see #stage.
  STAGES = {
    "pre_dev" => "Pre-dev", "dev" => "Dev", "post_dev" => "Post-dev",
    "review_pr" => "Review PR", "deploy" => "Deploy", "done" => "Done"
  }.freeze
  # Columns where Rich is the one who acts next.
  WAITING_ON_RICH = %w[planned pr_ready].freeze

  class InvalidTransition < StandardError; end

  # Set on items Rich adds from the board: no push or "got it" email to himself.
  attribute :skip_notifications, :boolean, default: false

  MAX_FILES     = 10
  MAX_FILE_SIZE = 15.megabytes
  # Photos (incl. iPhone HEIC), PDFs, and the office/text files a kitchen
  # manager might forward. Anything else is refused rather than stored.
  ALLOWED_TYPES = %w[
    image/png image/jpeg image/gif image/webp image/heic image/heif
    application/pdf text/plain text/csv
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.openxmlformats-officedocument.presentationml.presentation
    application/msword application/vnd.ms-excel
  ].freeze

  validates :message, presence: true, length: { maximum: 10_000 }
  validates :status, inclusion: { in: STATUSES }
  validate :attachments_are_acceptable
  # The mini reports this; only a GitHub pull request link is ever stored.
  PR_URL = %r{\Ahttps://github\.com/[\w.-]+/[\w.-]+/pull/\d+\z}
  validates :pr_url, format: { with: PR_URL }, allow_nil: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :open, -> { where.not(status: DONE) }
  # Items waiting on the mini: not stuck, not claimed by a live worker.
  scope :agent_queue, lambda {
    where(status: AGENT_STEPS.keys, agent_error: nil)
      .where("agent_claimed_at IS NULL OR agent_claimed_at < ?", CLAIM_TTL.ago)
      .order(:created_at)
  }

  after_create_commit -> { FeedbackSubmittedJob.perform_later(self) unless skip_notifications }

  def status_label
    return "Checks running" if stage == "post_dev"
    LABELS.fetch(status, status.humanize)
  end
  def sender_status_label = SENDER_LABELS.fetch(status, "In progress")
  def shipped? = status == "shipped"
  def done? = DONE.include?(status)
  def agent_step = AGENT_STEPS[status]
  def stuck? = agent_error.present?
  def waiting_on_rich? = WAITING_ON_RICH.include?(status) && !stuck?

  # Which board column the item sits in. "Post-dev" is a PR that exists but
  # isn't green yet; the agent is still on it until checks pass.
  def stage
    case status
    when "received", "planned", "needs_info" then "pre_dev"
    when "approved" then pr_url.present? ? "post_dev" : "dev"
    when "changes_requested", "in_progress" then "dev"
    when "pr_ready" then "review_pr"
    when "merge_requested" then "deploy"
    else "done"
    end
  end

  def stage_label = STAGES.fetch(stage)

  # The question the agent suggested asking, if its plan had one.
  def draft_question
    thread.reverse.find { |t| t["kind"] == "draft_question" }&.dig("body")
  end

  # ---- Rich's buttons ----

  # (1) Work on it.
  def approve!
    require_status!("planned")
    update!(status: "approved", approved_at: Time.current, agent_error: nil, agent_claimed_at: nil)
  end

  # Ask them: emails the sender a question they answer on their feedback page.
  def ask!(question)
    raise InvalidTransition, "Write the question first." if question.blank?
    raise InvalidTransition, "This item is already #{status_label}." if done?
    append_thread!("rich", question, kind: "question")
    update!(status: "needs_info", agent_claimed_at: nil)
    FeedbackMailer.question(self).deliver_later
  end

  # The sender's answer: back to the mini for a fresh plan.
  def answer!(body)
    require_status!("needs_info")
    raise InvalidTransition, "Write an answer first." if body.blank?
    append_thread!("sender", body, kind: "answer")
    update!(status: "received", plan: nil, planned_at: nil, agent_error: nil, agent_claimed_at: nil)
    FeedbackAlerts.push(self, "Answer from #{user.display_identifier}", body)
  end

  def close!(note = nil)
    raise InvalidTransition, "This item is already #{status_label}." if done?
    update!(status: "closed", closed_at: Time.current, reply: note.presence || reply, agent_claimed_at: nil)
    FeedbackMailer.closed(self).deliver_later if note.present?
  end

  def request_changes!(note)
    require_status!("pr_ready")
    raise InvalidTransition, "Say what to change." if note.blank?
    append_thread!("rich", note, kind: "changes")
    update!(status: "changes_requested", agent_claimed_at: nil)
  end

  # (2) Merge it. Only for the exact head Rich was looking at, and only while
  # checks are green; the mini re-verifies against GitHub before merging.
  def request_merge!(sha, note: nil)
    require_status!("pr_ready")
    unless sha.present? && sha == pr_head_sha
      raise InvalidTransition, "The PR changed since you opened it. Take another look first."
    end
    raise InvalidTransition, "Checks aren't green." unless pr_checks == "green"
    update!(status: "merge_requested", merge_requested_sha: sha, merge_requested_at: Time.current,
            ship_note: note.presence || ship_note, agent_claimed_at: nil)
  end

  # Back to Pre-dev for a fresh plan (a card dragged back, or a closed item
  # reopened). Not while a merge is in flight: that PR is already approved.
  def reset!
    raise InvalidTransition, "It's merging now; wait for it to finish." if status == "merge_requested"
    update!(status: "received", plan: nil, planned_at: nil, agent_error: nil, agent_claimed_at: nil,
            closed_at: nil)
  end

  # Clears a stuck item so the mini tries its step again.
  def retry!
    update!(agent_error: nil, agent_claimed_at: nil)
  end

  # ---- the mini's reports ----

  def claim!
    raise InvalidTransition, "Nothing for the agent to do (#{status_label})." unless agent_step
    raise InvalidTransition, "Stuck: retry it first." if stuck?
    if agent_claimed_at && agent_claimed_at > CLAIM_TTL.ago
      raise InvalidTransition, "Already claimed."
    end
    update!(agent_claimed_at: Time.current)
  end

  def record_plan!(plan_text, question: nil)
    require_status!("received")
    raise InvalidTransition, "Empty plan." if plan_text.blank?
    append_thread!("agent", question, kind: "draft_question") if question.present?
    update!(status: "planned", plan: plan_text, planned_at: Time.current, agent_claimed_at: nil)
    FeedbackAlerts.push(self, "Plan ready: #{excerpt(60)}", plan_text)
  end

  # The PR as it stands. Green checks move it to pr_ready (one push per new
  # head); pending or red keep it building under the same claim.
  def record_pr!(number:, url:, head_sha:, checks:, summary: nil, ship_note: nil)
    require_status!("approved", "changes_requested", "pr_ready")
    raise InvalidTransition, "PR number, url and head_sha are required." if [ number, url, head_sha ].any?(&:blank?)
    new_head = head_sha != pr_head_sha
    attrs = { pr_number: number, pr_url: url, pr_head_sha: head_sha, pr_checks: checks,
              pr_summary: summary.presence || pr_summary, ship_note: ship_note.presence || self.ship_note }
    if checks == "green"
      update!(attrs.merge(status: "pr_ready", pr_ready_at: Time.current, agent_claimed_at: nil))
      FeedbackAlerts.push(self, "Ready to merge: #{excerpt(60)}", "PR ##{number} · checks green. #{pr_summary}".strip) if new_head || saved_change_to_status?
    else
      update!(attrs)
    end
  end

  # Merged and the deploy verified: the sender gets the Live email with the
  # agent's note (which Rich could edit at Merge it).
  def record_shipped!(sha)
    require_status!("merge_requested")
    raise InvalidTransition, "Merged #{sha.to_s.first(7)}, but #{merge_requested_sha.to_s.first(7)} was approved." unless sha == merge_requested_sha
    ship!(ship_note)
    update!(agent_claimed_at: nil)
    FeedbackAlerts.push(self, "Live: #{excerpt(60)}", "Merged and deployed. #{user.display_identifier} was emailed.")
  end

  def record_error!(message)
    update!(agent_error: message.to_s.first(2_000).presence || "Unknown error", agent_claimed_at: nil)
    FeedbackAlerts.push(self, "Stuck: #{excerpt(60)}", agent_error, level: "warning")
  end

  # Marks it shipped (with an optional note to the sender) and emails them.
  # Only the first transition sends, so re-saving never mails twice.
  def ship!(note = nil)
    first_time = !shipped?
    update!(status: "shipped", reply: note.presence || reply, shipped_at: shipped_at || Time.current)
    FeedbackMailer.shipped(self).deliver_later if first_time
  end

  # "the first 80 characters…" for push titles and list rows.
  def excerpt(length = 80)
    message.to_s.squish.truncate(length)
  end

  private

  def require_status!(*allowed)
    return if allowed.include?(status)
    raise InvalidTransition, "Can't do that while it's #{status_label}."
  end

  def append_thread!(from, body, kind:)
    self.thread = thread + [ { "from" => from, "kind" => kind, "body" => body.to_s.strip, "at" => Time.current.iso8601 } ]
  end

  def attachments_are_acceptable
    return unless attachments.attached?

    errors.add(:attachments, "can be at most #{MAX_FILES} files") if attachments.size > MAX_FILES
    attachments.each do |file|
      blob = file.blob
      if blob.byte_size > MAX_FILE_SIZE
        errors.add(:attachments, "#{blob.filename} is over #{MAX_FILE_SIZE / 1.megabyte} MB")
      end
      unless ALLOWED_TYPES.include?(blob.content_type)
        errors.add(:attachments, "#{blob.filename} is not a photo, PDF, or document we can take")
      end
    end
  end
end
