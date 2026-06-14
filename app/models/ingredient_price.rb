# One observed price for one ingredient, pulled from a grocery receipt line.
# These accumulate into a price history the grocery estimator reads from, so
# week-over-week the estimates stop being guesses and start being real.
class IngredientPrice < ApplicationRecord
  belongs_to :grocery_receipt, optional: true

  validates :canonical_name, presence: true
  validates :unit_price_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Most recent observed price per canonical ingredient name, as a lookup hash:
  #   { "chicken breast" => <IngredientPrice>, ... }
  # Used as a pricing hint when building a future grocery estimate. Bounded to a
  # recent window so stale prices age out.
  def self.recent_by_name(since: 120.days.ago.to_date)
    where("observed_on >= ?", since)
      .order(observed_on: :desc, id: :desc)
      .group_by(&:canonical_name)
      .transform_values(&:first)
  end

  def unit_price_dollars
    unit_price_cents / 100.0
  end
end
