class KitchenSnapshot < ApplicationRecord
  has_many :kitchen_events, dependent: :destroy

  validates :taken_on, presence: true, uniqueness: true

  scope :latest, -> { order(taken_on: :desc).first }

  def self.latest_before(date)
    where("taken_on < ?", date).order(taken_on: :desc).first
  end
end
