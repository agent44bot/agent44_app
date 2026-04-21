require "net/http"
require "json"
require "uri"

namespace :jobs do
  desc "Geocode job locations via OpenStreetMap Nominatim"
  task geocode: :environment do
    skip_patterns = /\b(remote|anywhere|distributed|see listing|united states)\b/i

    jobs = Job.where(latitude: nil)
              .where.not(location: [ nil, "" ])
              .where.not("location REGEXP ?", skip_patterns.source)

    # SQLite doesn't support REGEXP by default, filter in Ruby
    jobs = Job.where(latitude: nil).where.not(location: [ nil, "" ])
    jobs = jobs.to_a.reject { |j| j.location.match?(skip_patterns) }

    puts "Geocoding #{jobs.size} jobs..."
    geocoded = 0
    failed = 0
    cache = {}

    jobs.each_with_index do |job, i|
      location = job.location.strip

      if cache.key?(location)
        lat, lng = cache[location]
        if lat
          job.update_columns(latitude: lat, longitude: lng)
          geocoded += 1
        end
        next
      end

      begin
        uri = URI("https://nominatim.openstreetmap.org/search")
        uri.query = URI.encode_www_form(q: location, format: "json", limit: 1)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "Agent44Labs/1.0 (agent44labs.com)"

        response = http.request(request)
        results = JSON.parse(response.body)

        if results.any?
          lat = results[0]["lat"].to_f
          lng = results[0]["lon"].to_f
          job.update_columns(latitude: lat, longitude: lng)
          cache[location] = [ lat, lng ]
          geocoded += 1
          puts "  [#{i + 1}/#{jobs.size}] #{location} => #{lat}, #{lng}"
        else
          cache[location] = [ nil, nil ]
          failed += 1
          puts "  [#{i + 1}/#{jobs.size}] #{location} => NOT FOUND"
        end

        sleep 1 # Nominatim rate limit
      rescue => e
        failed += 1
        puts "  [#{i + 1}/#{jobs.size}] #{location} => ERROR: #{e.message}"
        sleep 1
      end
    end

    puts "\nDone. Geocoded: #{geocoded}, Failed: #{failed}"
    puts "Total jobs with coordinates: #{Job.where.not(latitude: nil).count}"
  end
end
