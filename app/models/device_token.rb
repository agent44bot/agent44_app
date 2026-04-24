class DeviceToken < ApplicationRecord
  belongs_to :user, optional: true

  validates :token, presence: true, uniqueness: true
  validates :platform, presence: true

  scope :active, -> { where(active: true) }
  scope :ios, -> { where(platform: "ios") }
  scope :for_user, ->(user) { where(user_id: user.is_a?(User) ? user.id : user) }
end
