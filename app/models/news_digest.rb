class NewsDigest < ApplicationRecord
  validates :date, presence: true, uniqueness: true
  validates :summary, presence: true
end
