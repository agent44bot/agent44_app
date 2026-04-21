class SocialPostLog < ApplicationRecord
  validates :event_url, presence: true, uniqueness: true

  def copied?
    copied_at.present?
  end

  def posted?
    posted_at.present?
  end
end
