class KitchenEvent < ApplicationRecord
  belongs_to :kitchen_snapshot

  validates :url, presence: true

  scope :upcoming, -> { where("start_at >= ?", Time.current).order(:start_at) }
  scope :sold_out, -> { where("LOWER(availability) LIKE ? OR LOWER(availability) LIKE ?", "%soldout%", "%closed%") }

  def sold_out?
    av = availability.to_s.downcase
    av.include?("soldout") || av.include?("closed")
  end

  # Canonical status bucket for filter chips + CSS targeting.
  # "soldout" takes priority over "closed" — Laura's request: when both
  # appear on the event page, show "Sold Out" on the list.
  def availability_status
    d = availability.to_s.downcase
    case d
    when /soldout/  then "soldout"
    when /closed/   then "closed"
    when /limited/  then "limited"
    when /instock/  then "instock"
    else                 "other"
    end
  end
end
