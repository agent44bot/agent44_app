class DeviceToken < ApplicationRecord
  validates :token, presence: true, uniqueness: true
  validates :platform, presence: true

  scope :active, -> { where(active: true) }
  scope :ios, -> { where(platform: "ios") }
end
