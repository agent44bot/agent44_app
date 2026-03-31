# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

require "json"

jobs_file = Rails.root.join("db/seeds/jobs.json")

if jobs_file.exist?
  jobs = JSON.parse(jobs_file.read)
  created = 0

  jobs.each do |attrs|
    job = Job.find_or_initialize_by(source: attrs["source"], url: attrs["url"])
    if job.new_record?
      job.assign_attributes(attrs)
      created += 1 if job.save
    end
  end

  puts "Seeded #{created} jobs (#{jobs.size - created} already existed)"
else
  puts "No jobs seed file found at db/seeds/jobs.json"
end

# Seed scraper sources
load Rails.root.join("db/seeds/scrapers.rb")
