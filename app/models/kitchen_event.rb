class KitchenEvent < ApplicationRecord
  belongs_to :kitchen_snapshot

  validates :url, presence: true

  scope :upcoming, -> { where("start_at >= ?", Time.current).order(:start_at) }
  scope :sold_out, -> { where("LOWER(availability) LIKE ? OR LOWER(availability) LIKE ?", "%soldout%", "%closed%") }

  def sold_out?
    av = availability.to_s.downcase
    av.include?("soldout") || av.include?("closed")
  end
end
