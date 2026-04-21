require "net/http"
require "uri"

namespace :jobs do
  desc "Deactivate jobs with dead URLs (404/410/unreachable)"
  task check_urls: :environment do
    jobs = Job.active.where.not(url: [ nil, "" ])
    total = jobs.count
    dead = 0
    alive = 0
    errors = 0

    puts "Checking #{total} job URLs..."

    jobs.find_each.with_index do |job, i|
      status = check_url(job.url)

      if status == :dead
        job.update_columns(active: false)
        dead += 1
        puts "  [#{i + 1}/#{total}] DEAD (deactivated): #{job.title} — #{job.url}"
      elsif status == :error
        errors += 1
        # Don't deactivate on network errors — might be temporary
      else
        alive += 1
      end

      # Print progress every 50 jobs
      if (i + 1) % 50 == 0
        puts "  Progress: #{i + 1}/#{total} (alive: #{alive}, dead: #{dead}, errors: #{errors})"
      end

      sleep 0.5 # Be polite to external servers
    end

    puts "\nDone."
    puts "  Alive: #{alive}"
    puts "  Dead (deactivated): #{dead}"
    puts "  Errors (skipped): #{errors}"
    puts "  Total active jobs remaining: #{Job.active.count}"
  end
end

def check_url(url)
  uri = URI.parse(url)
  return :error unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.open_timeout = 10
  http.read_timeout = 10

  # Use HEAD first, fall back to GET if HEAD not allowed
  begin
    response = http.request_head(uri.request_uri, { "User-Agent" => "Agent44Labs/1.0 (agent44labs.com)" })
  rescue
    begin
      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = "Agent44Labs/1.0 (agent44labs.com)"
      response = http.request(request)
    rescue => e
      return :error
    end
  end

  # Follow redirects (up to 3)
  redirects = 0
  while response.is_a?(Net::HTTPRedirection) && redirects < 3
    redirect_url = response["location"]
    break if redirect_url.nil?

    # Handle relative redirects
    redirect_uri = URI.parse(redirect_url) rescue nil
    break if redirect_uri.nil?
    redirect_uri = uri + redirect_uri unless redirect_uri.host

    begin
      rhttp = Net::HTTP.new(redirect_uri.host, redirect_uri.port)
      rhttp.use_ssl = redirect_uri.scheme == "https"
      rhttp.open_timeout = 10
      rhttp.read_timeout = 10
      response = rhttp.request_head(redirect_uri.request_uri, { "User-Agent" => "Agent44Labs/1.0 (agent44labs.com)" })
    rescue
      return :error
    end
    redirects += 1
  end

  case response.code.to_i
  when 200..399
    :alive
  when 404, 410
    :dead
  else
    :error # Don't deactivate on 403, 429, 500, etc.
  end
rescue => e
  :error
end
