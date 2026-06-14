class Expense < ApplicationRecord
  validates :tax_year, :incurred_on, :vendor, :amount, :fingerprint, presence: true
  validates :fingerprint, uniqueness: true

  before_validation :set_tax_year

  scope :for_year, ->(year) { where(tax_year: year) }
  scope :counted,  -> { where(excluded: false) }
  scope :flagged,  -> { where.not(review_flag: [ nil, "" ]) }

  # Stable identity for a transaction so re-uploading the same RocketMoney
  # export does not create duplicates. Based on date + vendor + amount + the
  # raw description.
  def self.fingerprint_for(incurred_on:, vendor:, amount:, raw_description:)
    raw = [ incurred_on, vendor.to_s.strip.downcase, format("%.2f", amount.to_f), raw_description.to_s.strip.downcase ].join("|")
    Digest::SHA256.hexdigest(raw)
  end

  # Category totals for a year, excluding the rows the user has marked out.
  def self.category_totals(year)
    for_year(year).counted.group(:category).sum(:amount)
  end

  def self.year_total(year)
    for_year(year).counted.sum(:amount)
  end

  private

  def set_tax_year
    self.tax_year ||= incurred_on&.year
  end
end
