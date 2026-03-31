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
end
