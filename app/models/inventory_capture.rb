# A single logged product: a photo + quantity + unit price + category, captured
# on a phone and accumulated into a monthly record you export to a spreadsheet
# (CSV). Standalone — it does NOT touch the on-hand ledger (InventoryMovement);
# it's a purchase/tracking log for reconciling with the seller.
class InventoryCapture < ApplicationRecord
  belongs_to :user, optional: true
  has_one_attached :photo

  CATEGORIES = InventoryItem::CATEGORIES

  validates :quantity,   numericality: { greater_than: 0, only_integer: true }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_validation :default_captured_at

  scope :recent,   -> { order(captured_at: :desc, id: :desc) }
  scope :in_range, ->(from, to) { where(captured_at: from..to) }

  # Line total = qty × unit price (0 when no price recorded).
  def line_total
    quantity * (unit_price || 0)
  end

  private

  def default_captured_at
    self.captured_at ||= Time.current
  end
end
