namespace :jobs do
  desc "Run all enabled scrapers that are due based on their schedule"
  task scrape_all: :environment do
    puts "=" * 50
    puts "Agent44 Job Scraper (Rails)"
    puts "Started at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "=" * 50

    total_created = 0
    total_updated = 0

    ScraperSource.enabled.find_each do |source|
      print "Scraping #{source.name}..."
      result = source.run!

      if result[:error]
        puts " ERROR: #{result[:error]}"
      else
        puts " #{result[:created]} created, #{result[:updated]} updated (#{result[:total]} found)"
      end

      total_created += result[:created]
      total_updated += result[:updated]
    end

    puts "=" * 50
    puts "Done! #{total_created} new jobs created, #{total_updated} updated"
    puts "=" * 50
  end

  desc "Scrape locally and push results to production API"
  task scrape_and_push: :environment do
    require "net/http"
    require "json"
    require "uri"
    require "dotenv"
    Dotenv.load

    production_url = ENV.fetch("PRODUCTION_URL", "https://agent44labs.com")
    api_token = ENV.fetch("API_TOKEN")
    endpoint = "#{production_url}/api/v1/jobs"

    puts "=" * 50
    puts "Agent44 Job Scraper (Local -> Production)"
    puts "Started at #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "Pushing to #{production_url}"
    puts "=" * 50

    total_created = 0
    total_updated = 0

    ScraperSource.enabled.find_each do |source|
      print "Scraping #{source.name}..."

      klass = source.scraper_class
      unless klass
        puts " ERROR: No scraper class"
        next
      end

      if source.api_key_name.present? && !source.api_key_set?
        puts " SKIPPED: Missing ENV[#{source.api_key_name}]"
        next
      end

      begin
        scraper = klass.new(source)
        jobs = scraper.call.select { |j| j[:url].present? }

        if jobs.empty?
          puts " 0 found"
          source.update(last_run_at: Time.current, last_run_status: "success", last_run_jobs_found: 0, last_run_error: nil)
          sync_scraper_status(production_url, api_token, source.slug, "success", 0)
          next
        end

        # POST to production API
        uri = URI(endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 15
        http.read_timeout = 60

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{api_token}"
        request["Content-Type"] = "application/json"
        request.body = { jobs: jobs }.to_json

        response = http.request(request)
        result = JSON.parse(response.body)

        created = result["created"] || 0
        updated = result["updated"] || 0
        total_created += created
        total_updated += updated

        source.update(last_run_at: Time.current, last_run_status: "success", last_run_jobs_found: jobs.size, last_run_error: nil)
        sync_scraper_status(production_url, api_token, source.slug, "success", jobs.size)
        puts " #{created} created, #{updated} updated (#{jobs.size} found)"
      rescue StandardError => e
        source.update(last_run_at: Time.current, last_run_status: "error", last_run_jobs_found: 0, last_run_error: e.message)
        sync_scraper_status(production_url, api_token, source.slug, "error", 0, e.message)
        puts " ERROR: #{e.message}"
      end
    end

    puts "=" * 50
    puts "Done! #{total_created} new jobs created, #{total_updated} updated"
    puts "=" * 50
  end

  desc "Run a specific scraper by slug (e.g. rake jobs:scrape[remoteok])"
  task :scrape, [:slug] => :environment do |_t, args|
    source = ScraperSource.find_by!(slug: args[:slug])
    puts "Running #{source.name}..."
    result = source.run!

    if result[:error]
      puts "ERROR: #{result[:error]}"
    else
      puts "#{source.name}: #{result[:created]} created, #{result[:updated]} updated (#{result[:total]} found)"
    end
  end

  def sync_scraper_status(production_url, api_token, slug, status, jobs_found, error = nil)
    uri = URI("#{production_url}/api/v1/scrapers/#{slug}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 30
    http.read_timeout = 30

    request = Net::HTTP::Patch.new(uri)
    request["Authorization"] = "Bearer #{api_token}"
    request["Content-Type"] = "application/json"
    request.body = {
      last_run_at: Time.current.iso8601,
      last_run_status: status,
      last_run_jobs_found: jobs_found,
      last_run_error: error
    }.to_json

    http.request(request)
  rescue => e
    puts " (sync warning: #{e.message})"
  end
end
