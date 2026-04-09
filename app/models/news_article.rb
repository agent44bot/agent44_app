class NewsArticle < ApplicationRecord
  validates :title, :url, :source, presence: true
  validates :url, uniqueness: true

  scope :unused, -> { where(used_at: nil) }
  scope :used, -> { where.not(used_at: nil) }
  scope :recent, -> { order(published_at: :desc) }

  def mark_as_used!
    update!(used_at: Time.current)
  end
end
