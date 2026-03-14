class Post < ApplicationRecord
  belongs_to :user
  has_rich_text :body

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :published, -> { where(published: true).order(published_at: :desc) }
  scope :drafts, -> { where(published: false).order(updated_at: :desc) }

  before_validation :generate_slug, if: -> { slug.blank? && title.present? }

  def to_param
    slug
  end

  private

  def generate_slug
    self.slug = title.parameterize
    count = Post.where("slug LIKE ?", "#{slug}%").count
    self.slug = "#{slug}-#{count + 1}" if count > 0
  end
end
