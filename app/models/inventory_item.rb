class InventoryItem < ApplicationRecord
  has_many :movements, class_name: "InventoryMovement", dependent: :destroy

  CATEGORIES = %w[wine spirit beer mixer other].freeze

  validates :name, presence: true
  validates :units_per_case, numericality: { greater_than: 0 }
  validates :barcode,      uniqueness: true, allow_nil: true
  validates :case_barcode, uniqueness: true, allow_nil: true

  # Blank codes become NULL so the unique indexes don't collide on "".
  normalizes :barcode,      with: ->(c) { c.to_s.strip.presence }
  normalizes :case_barcode, with: ->(c) { c.to_s.strip.presence }

  scope :by_name, -> { order(Arel.sql("LOWER(name)")) }

  # Resolve a scanned code to an item, matching either the bottle UPC or the
  # case code. Returns nil for unknown codes (→ caller offers a setup form).
  def self.find_by_code(code)
    code = code.to_s.strip
    return nil if code.blank?
    where(barcode: code).or(where(case_barcode: code)).first
  end

  # item_id => net units on hand (Σ in − Σ out), in one grouped query. Items
  # with no movements are absent (treat as 0).
  def self.on_hand_by_item
    InventoryMovement.group(:inventory_item_id)
      .sum(Arel.sql("CASE WHEN direction = 'in' THEN quantity ELSE -quantity END"))
  end

  # Current units on hand for this single item.
  def on_hand
    movements.sum(Arel.sql("CASE WHEN direction = 'in' THEN quantity ELSE -quantity END"))
  end

  def low_stock?(level = on_hand)
    par_level.present? && level <= par_level
  end

  # Units a scanned code implies: a case code adds a full case, a bottle code
  # is one unit.
  def units_for_code(code)
    code.to_s.strip == case_barcode.to_s ? units_per_case : 1
  end
end
