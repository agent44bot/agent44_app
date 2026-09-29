class PageView < ApplicationRecord
  belongs_to :user, optional: true

  scope :today, -> { where(created_at: Date.current.all_day) }
  scope :this_week, -> { where(created_at: Date.current.beginning_of_week..Time.current) }
  scope :this_month, -> { where(created_at: Date.current.beginning_of_month..Time.current) }
  scope :last_30_days, -> { where(created_at: 30.days.ago..Time.current) }
  scope :with_location, -> { where.not(latitude: nil, longitude: nil) }

  # A user counts as "online" if they loaded a page this recently. PageView,
  # not Session: Session.updated_at freezes at sign-in (persistent cookies).
  ONLINE_WINDOW = 5.minutes

  # Subset of user_ids with a page view inside ONLINE_WINDOW, as a Set.
  def self.online_user_ids(user_ids)
    return Set.new if user_ids.blank?
    where(user_id: user_ids, created_at: ONLINE_WINDOW.ago..).distinct.pluck(:user_id).to_set
  end
end
