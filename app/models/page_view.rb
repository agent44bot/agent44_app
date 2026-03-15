class PageView < ApplicationRecord
  belongs_to :user, optional: true

  scope :today, -> { where(created_at: Date.current.all_day) }
  scope :this_week, -> { where(created_at: Date.current.beginning_of_week..Time.current) }
  scope :this_month, -> { where(created_at: Date.current.beginning_of_month..Time.current) }
  scope :last_30_days, -> { where(created_at: 30.days.ago..Time.current) }
  scope :with_location, -> { where.not(latitude: nil, longitude: nil) }
end
