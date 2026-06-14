class RevenueEntry < ApplicationRecord
  validates :received_on, :source, :amount, presence: true

  before_validation :set_tax_year

  scope :for_year, ->(year) { where(tax_year: year) }

  def self.year_total(year)
    for_year(year).sum(:amount)
  end

  private

  def set_tax_year
    self.tax_year ||= received_on&.year
  end
end
