# A grocery receipt Lora/Sam uploads after shopping for a week of classes.
# The image is parsed (Opus vision) into IngredientPrice rows so future
# grocery estimates use real observed prices instead of guesses.
class GroceryReceipt < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  has_many :ingredient_prices, dependent: :nullify
  has_one_attached :image

  STATUSES = %w[pending parsed failed].freeze
  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :for_week, ->(from, to) { where(week_start: from, week_end: to) }

  def parsed? = status == "parsed"
  def failed? = status == "failed"

  def total_dollars
    total_cents ? total_cents / 100.0 : nil
  end
end
