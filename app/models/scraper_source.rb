class ScraperSource < ApplicationRecord
  SCHEDULES = %w[every_6h twice_daily daily every_3d].freeze

  attribute :search_terms_text, :string
  attribute :config_text, :string

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/, message: "only lowercase letters, numbers, and underscores" }
  validates :schedule, inclusion: { in: SCHEDULES }

  scope :enabled, -> { where(enabled: true) }

  def api_key
    api_key_name.present? ? ENV[api_key_name] : nil
  end

  def api_key_set?
    api_key_name.blank? || ENV[api_key_name].present?
  end

  # Maps slug prefixes to their parent scraper class.
  # e.g. google_jobs_crypto -> Scrapers::GoogleJobs
  SLUG_ALIASES = {}.freeze

  def scraper_class
    class_name = SLUG_ALIASES[slug] || "Scrapers::#{slug.camelize}"
    class_name.constantize
  rescue NameError
    nil
  end

  def run!
    Scrapers::Runner.new(self).call
  end

  def schedule_label
    case schedule
    when "every_6h" then "Every 6 hours"
    when "twice_daily" then "Twice daily"
    when "daily" then "Daily"
    when "every_3d" then "Every 3 days"
    else schedule
    end
  end

  def cost_label
    api_key_name.present? ? "Free tier" : "Free"
  end

  def status_color
    case last_run_status
    when "success" then "green"
    when "error" then "red"
    when "partial" then "yellow"
    else "gray"
    end
  end
end
