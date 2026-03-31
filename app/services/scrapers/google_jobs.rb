module Scrapers
  class GoogleJobs < Base
    def call
      api_key = source.api_key
      return [] unless api_key.present?

      queries = search_terms.presence || [
        "SDET software development engineer in test",
        "QA test automation engineer",
        "senior quality engineer automation"
      ]
      jobs = []

      queries.each do |query|
        params = URI.encode_www_form(
          engine: "google_jobs",
          q: query,
          hl: "en",
          gl: "us",
          api_key: api_key
        )
        url = "https://serpapi.com/search.json?#{params}"

        data = fetch_json(url)
        next unless data&.dig("jobs_results")

        data["jobs_results"].each do |item|
          title = item["title"].to_s
          company = item["company_name"].to_s
          location = item["location"].to_s
          job_id = item["job_id"].to_s

          # Find apply link
          apply_link = ""
          apply_options = item["apply_options"]
          if apply_options.is_a?(Array) && apply_options.any?
            apply_link = apply_options[0]["link"].to_s
          end
          if apply_link.blank?
            related = item["related_links"]
            apply_link = related[0]["link"].to_s if related.is_a?(Array) && related.any?
          end
          if apply_link.blank?
            apply_link = "https://www.google.com/search?q=#{ERB::Util.url_encode("#{title} #{company}")}&ibp=htl;jobs#htidocid=#{job_id}"
          end

          # Detect original source
          detected_source = "google_jobs"
          if apply_options.is_a?(Array) && apply_options.any?
            publisher = (apply_options[0]["title"] || "").downcase
            if publisher.include?("linkedin")
              detected_source = "linkedin"
            elsif publisher.include?("indeed")
              detected_source = "indeed"
            elsif publisher.include?("glassdoor")
              detected_source = "glassdoor"
            end
          end

          highlights = item["detected_extensions"] || {}

          jobs << {
            title: [ title, company, location ].compact_blank.join(" - "),
            company: company,
            location: location,
            url: apply_link,
            salary: highlights["salary"].to_s,
            source: detected_source,
            category: categorize(title),
            description: (item["description"] || "").truncate(2000, omission: ""),
            posted_at: highlights["posted_at"].to_s,
            external_id: job_id.present? ? "google-jobs-#{job_id}" : ""
          }
        end
      end

      # Deduplicate by URL
      jobs.select { |j| j[:url].present? }.uniq { |j| j[:url] }
    end
  end
end
