module Scrapers
  class Runner
    attr_reader :source

    def initialize(source)
      @source = source
    end

    def call
      unless source.enabled?
        return { created: 0, updated: 0, total: 0, error: "Source is disabled" }
      end

      klass = source.scraper_class
      unless klass
        source.update(last_run_status: "error", last_run_error: "No scraper class found for #{source.slug}", last_run_at: Time.current)
        return { created: 0, updated: 0, total: 0, error: "No scraper class" }
      end

      if source.api_key_name.present? && !source.api_key_set?
        source.update(last_run_status: "error", last_run_error: "Missing ENV[#{source.api_key_name}]", last_run_at: Time.current)
        return { created: 0, updated: 0, total: 0, error: "Missing API key" }
      end

      scraper = klass.new(source)
      jobs = scraper.call

      # Filter out jobs with no URL
      jobs = jobs.select { |j| j[:url].present? }

      result = JobImporter.new(jobs).call

      source.update(
        last_run_at: Time.current,
        last_run_status: "success",
        last_run_jobs_found: jobs.size,
        last_run_error: nil
      )

      result
    rescue StandardError => e
      source.update(
        last_run_at: Time.current,
        last_run_status: "error",
        last_run_jobs_found: 0,
        last_run_error: "#{e.class}: #{e.message}"
      )
      Rails.logger.error("[Scraper:#{source.slug}] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      { created: 0, updated: 0, total: 0, error: e.message }
    end
  end
end
