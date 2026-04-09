require "rake"

class ScrapeJobsJob < ApplicationJob
  queue_as :default

  def perform
    jobs_before = Job.count

    Rails.application.load_tasks unless Rake::Task.task_defined?("jobs:scrape_and_push")
    Rake::Task["jobs:scrape_and_push"].reenable
    Rake::Task["jobs:scrape_and_push"].invoke

    new_jobs = Job.count - jobs_before

    if new_jobs.zero?
      Notification.notify!(
        level: "warning",
        source: "scrape_jobs",
        title: "Scraper run created 0 new jobs",
        body: "jobs:scrape_and_push completed without errors but no new Job records were created. Possible source breakage — check the Scrapers admin page.",
        telegram: true
      )
    else
      Notification.notify!(
        level: "success",
        source: "scrape_jobs",
        title: "Scraper run complete",
        body: "Created #{new_jobs} new jobs."
      )
    end
  rescue => e
    Notification.notify!(
      level: "error",
      source: "scrape_jobs",
      title: "ScrapeJobsJob crashed",
      body: "#{e.class}: #{e.message}\n\n#{e.backtrace&.first(5)&.join("\n")}",
      telegram: true
    )
    raise
  end
end
