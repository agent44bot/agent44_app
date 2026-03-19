class Job < ApplicationRecord
  CATEGORIES = %w[full_time part_time contract ai].freeze

  validates :title, :url, :category, presence: true
  validates :url, uniqueness: { scope: :source }
  validates :category, inclusion: { in: CATEGORIES }

  scope :active, -> { where(active: true) }
  scope :by_category, ->(cat) { where(category: cat) if cat.present? }
  scope :by_source, ->(src) { where(source: src) if src.present? }
  scope :recent, -> { order(created_at: :desc) }
  scope :search, ->(q) {
    where("title LIKE ? OR company LIKE ? OR source LIKE ?", "%#{q}%", "%#{q}%", "%#{q}%") if q.present?
  }
  scope :posted_today, -> { where(created_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :by_salary_desc, -> {
    order(Arel.sql("CASE WHEN salary IS NOT NULL AND salary != '' THEN 0 ELSE 1 END, CAST(REPLACE(REPLACE(SUBSTR(salary, 1, INSTR(salary || ' ', ' ') - 1), '$', ''), ',', '') AS REAL) DESC"))
  }
  scope :by_salary_asc, -> {
    order(Arel.sql("CASE WHEN salary IS NOT NULL AND salary != '' THEN 0 ELSE 1 END, CAST(REPLACE(REPLACE(SUBSTR(salary, 1, INSTR(salary || ' ', ' ') - 1), '$', ''), ',', '') AS REAL) ASC"))
  }

  BITCOIN_SOURCES = %w[bitcoinjobs bitcoinerjobs bitcoin_bamboohr].freeze

  def posted_today?
    created_at&.to_date == Time.current.to_date
  end

  def bitcoin_job?
    BITCOIN_SOURCES.include?(source)
  end
end
