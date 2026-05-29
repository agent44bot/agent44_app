class InventoryMovement < ApplicationRecord
  belongs_to :inventory_item
  belongs_to :user, optional: true

  DIRECTIONS = %w[in out].freeze

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :quantity,  numericality: { greater_than: 0, only_integer: true }

  before_validation :default_occurred_at

  scope :recent,    -> { order(occurred_at: :desc, id: :desc) }
  scope :inbound,   -> { where(direction: "in") }
  scope :outbound,  -> { where(direction: "out") }

  def signed_quantity
    direction == "in" ? quantity : -quantity
  end

  private

  def default_occurred_at
    self.occurred_at ||= Time.current
  end
end
