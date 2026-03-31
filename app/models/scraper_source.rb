class ScraperSource < ApplicationRecord
  SCHEDULES = %w[every_6h twice_daily daily].freeze

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

  def scraper_class
    "Scrapers::#{slug.camelize}".constantize
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
    else schedule
    end
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
