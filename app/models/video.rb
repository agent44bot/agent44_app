class Video < ApplicationRecord
  validates :title, :youtube_id, presence: true

  scope :published, -> { where(published: true).order(position: :asc, created_at: :desc) }

  def thumbnail_url
    "https://img.youtube.com/vi/#{youtube_id}/hqdefault.jpg"
  end

  def embed_url
    "https://www.youtube.com/embed/#{youtube_id}"
  end

  def youtube_url=(url)
    self.youtube_id = self.class.extract_youtube_id(url)
  end

  def self.extract_youtube_id(url)
    return url if url.present? && !url.include?("/") && !url.include?(".")
    match = url&.match(/(?:youtu\.be\/|youtube\.com\/(?:watch\?v=|embed\/|shorts\/))([a-zA-Z0-9_-]{11})/)
    match ? match[1] : url
  end
end
