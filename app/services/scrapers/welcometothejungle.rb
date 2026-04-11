module Scrapers
  class Welcometothejungle < Base
    DEFAULT_ALGOLIA_URL = "https://%{app_id}-dsn.algolia.net/1/indexes/wttj_jobs_production_en/query"

    def call
      algolia_creds = Rails.application.credentials.algolia || {}
      app_id = config["algolia_app_id"] || algolia_creds[:app_id] || ENV["ALGOLIA_APP_ID"]
      api_key = config["algolia_api_key"] || algolia_creds[:api_key] || ENV["ALGOLIA_API_KEY"]
      algolia_url = config["algolia_url"] || (DEFAULT_ALGOLIA_URL % { app_id: app_id })

      unless app_id.present? && api_key.present?
        Rails.logger.warn("[Scraper:welcometothejungle] Missing Algolia credentials. Set in Rails credentials or scraper config.")
        return []
      end

      queries = search_terms.presence || %w[SDET QA\ engineer test\ automation quality\ engineer]

      headers = {
        "X-Algolia-Application-Id" => app_id,
        "X-Algolia-API-Key" => api_key,
        "Referer" => "https://www.welcometothejungle.com/"
      }

      seen_ids = Set.new
      jobs = []

      queries.each do |query|
        data = post_json(algolia_url, body: { query: query, hitsPerPage: 50 }, headers: headers)
        next unless data

        (data["hits"] || []).each do |hit|
          obj_id = hit["objectID"].to_s
          next if seen_ids.include?(obj_id)
          seen_ids.add(obj_id)

          name = hit["name"].to_s
          next unless relevant?(name)

          org = hit["organization"] || {}
          company = org["name"].to_s
          org_slug = org["slug"].to_s
          job_slug = hit["slug"].to_s

          offices = hit["offices"] || []
          location = if offices.any?
            [ offices[0]["city"], offices[0]["country"] ].compact_blank.join(", ")
          elsif hit["remote"]
            "Remote"
          else
            ""
          end

          sal_min = hit["salary_yearly_minimum"] || hit["salary_minimum"]
          sal_max = hit["salary_maximum"]
          sal_currency = hit["salary_currency"].to_s
          salary = if sal_min && sal_max
            "#{sal_currency}#{sal_min.to_i.to_fs(:delimited)} - #{sal_currency}#{sal_max.to_i.to_fs(:delimited)}"
          elsif sal_min
            "#{sal_currency}#{sal_min.to_i.to_fs(:delimited)}+"
          else
            ""
          end

          url = org_slug.present? && job_slug.present? ? "https://www.welcometothejungle.com/en/companies/#{org_slug}/jobs/#{job_slug}" : ""

          jobs << {
            title: name,
            company: company,
            location: location,
            url: url,
            salary: salary,
            source: "welcometothejungle",
            category: categorize(name),
            ai_augmented: ai_augmented?(name),
            description: hit["summary"].to_s,
            posted_at: hit["published_at"].to_s,
            external_id: "wttj-#{obj_id}"
          }
        end
      end

      jobs
    end
  end
end
