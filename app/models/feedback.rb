# Feedback a signed-in user sends from the Feedback button (message plus
# optional screenshots or files). Rich is pushed on submit and gets an email
# copy; the sender gets an acknowledgement, and another email when Rich marks
# it shipped. See FeedbackSubmittedJob / FeedbackMailer.
class Feedback < ApplicationRecord
  belongs_to :user
  belongs_to :workspace, optional: true
  has_many_attached :attachments

  STATUSES = %w[received in_progress shipped closed].freeze
  LABELS = { "received" => "Received", "in_progress" => "In progress",
             "shipped" => "Live", "closed" => "Closed" }.freeze

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

  scope :recent_first, -> { order(created_at: :desc) }
  scope :open, -> { where(status: %w[received in_progress]) }

  after_create_commit -> { FeedbackSubmittedJob.perform_later(self) }

  def status_label = LABELS.fetch(status, status.humanize)
  def shipped? = status == "shipped"

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
