class Job < ApplicationRecord
  CATEGORIES = %w[full_time part_time contract ai].freeze

  validates :title, :url, :category, presence: true
  validates :url, uniqueness: { scope: :source }
  validates :category, inclusion: { in: CATEGORIES }

  scope :active, -> { where(active: true) }
  scope :by_category, ->(cat) { where(category: cat) if cat.present? }
  scope :by_source, ->(src) { where(source: src) if src.present? }
  scope :recent, -> { order(posted_at: :desc) }
  scope :search, ->(q) {
    where("title LIKE ? OR company LIKE ? OR source LIKE ?", "%#{q}%", "%#{q}%", "%#{q}%") if q.present?
  }
  scope :posted_today, -> { where(posted_at: Time.current.beginning_of_day..Time.current.end_of_day) }

  def posted_today?
    posted_at&.to_date == Time.current.to_date
  end
end
