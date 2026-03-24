class Job < ApplicationRecord
  CATEGORIES = %w[full_time part_time contract ai].freeze
  BITCOIN_SOURCES = %w[bitcoinjobs bitcoinerjobs bitcoin_bamboohr].freeze

  has_many :job_sources, dependent: :destroy

  validates :title, :url, :category, presence: true
  validates :url, uniqueness: { scope: :source }
  validates :category, inclusion: { in: CATEGORIES }

  before_validation :set_normalized_fields

  scope :active, -> { where(active: true) }
  scope :by_category, ->(cat) { where(category: cat) if cat.present? }
  scope :by_source, ->(src) {
    joins(:job_sources).where(job_sources: { source: src }).distinct if src.present?
  }
  scope :recent, -> { order(created_at: :desc) }
  scope :search, ->(q) {
    left_joins(:job_sources)
      .where("jobs.title LIKE ? OR jobs.company LIKE ? OR jobs.location LIKE ? OR job_sources.source LIKE ?", "%#{q}%", "%#{q}%", "%#{q}%", "%#{q}%")
      .distinct if q.present?
  }
  scope :posted_today, -> { where(created_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :remote, -> { where("location LIKE ? OR location LIKE ?", "%Remote%", "%Anywhere%") }
  scope :by_salary_desc, -> {
    order(Arel.sql("CASE WHEN salary IS NOT NULL AND salary != '' THEN 0 ELSE 1 END, CAST(REPLACE(REPLACE(SUBSTR(salary, 1, INSTR(salary || ' ', ' ') - 1), '$', ''), ',', '') AS REAL) DESC"))
  }
  scope :by_salary_asc, -> {
    order(Arel.sql("CASE WHEN salary IS NOT NULL AND salary != '' THEN 0 ELSE 1 END, CAST(REPLACE(REPLACE(SUBSTR(salary, 1, INSTR(salary || ' ', ' ') - 1), '$', ''), ',', '') AS REAL) ASC"))
  }

  def posted_today?
    created_at&.to_date == Time.current.to_date
  end

  def bitcoin_job?
    job_sources.any? { |js| BITCOIN_SOURCES.include?(js.source) }
  end

  def primary_source
    job_sources.min_by(&:created_at)
  end

  def multi_source?
    job_sources.size > 1
  end

  def source_names
    job_sources.map(&:source)
  end

  def self.normalize_title(t)
    return nil if t.blank?
    t.downcase.strip
      .gsub(/\s*\/\s*/, "/")          # normalize " / " to "/"
      .gsub(/\s*-\s*/, " - ")         # normalize dash spacing
      .gsub(/\s+/, " ")               # collapse whitespace
      .gsub(/[.,!\-]+\z/, "")         # strip trailing punctuation
      .strip
  end

  def self.normalize_company(c)
    return nil if c.blank?
    c.downcase.strip
      .gsub(/,?\s*(inc\.?|llc\.?|corp\.?|ltd\.?|co\.?|company|corporation|incorporated)\s*$/i, "")
      .gsub(/\s+/, " ").strip
  end

  private

  def set_normalized_fields
    self.normalized_title = self.class.normalize_title(title)
    self.normalized_company = self.class.normalize_company(company)
  end
end
