class Job < ApplicationRecord
  CATEGORIES = %w[full_time part_time contract ai].freeze

  validates :title, :url, :category, presence: true
  validates :url, uniqueness: { scope: :source }
  validates :category, inclusion: { in: CATEGORIES }

  scope :active, -> { where(active: true) }
  scope :by_category, ->(cat) { where(category: cat) if cat.present? }
  scope :recent, -> { order(posted_at: :desc) }
  scope :search, ->(q) {
    where("title LIKE ? OR company LIKE ?", "%#{q}%", "%#{q}%") if q.present?
  }
end
