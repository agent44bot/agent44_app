module Scrapers
  class Jsearch < Base
    def call
      api_key = source.api_key
      return [] unless api_key.present?

      queries = search_terms.presence || [ "SDET", "test automation engineer", "QA automation engineer" ]
      jobs = []

      queries.each do |query|
        params = URI.encode_www_form(
          query: query,
          page: "1",
          num_pages: "1",
          date_posted: "week",
          remote_jobs_only: "false"
        )
        url = "https://jsearch.p.rapidapi.com/search?#{params}"
        headers = {
          "x-rapidapi-key" => api_key,
          "x-rapidapi-host" => "jsearch.p.rapidapi.com"
        }

        data = fetch_json(url, headers: headers)
        next unless data&.dig("data")

        data["data"].each do |item|
          title = item["job_title"].to_s
          next unless relevant?(title)

          apply_link = ""
          apply_options = item["apply_options"]
          if apply_options.is_a?(Array) && apply_options.any?
            apply_link = apply_options[0]["apply_link"].to_s
          end
          apply_link = item["job_apply_link"].to_s if apply_link.blank?

          publisher = (item["job_publisher"] || "").downcase
          detected_source = if publisher.include?("indeed")
            "indeed"
          elsif publisher.include?("glassdoor")
            "glassdoor"
          elsif publisher.include?("linkedin")
            "linkedin"
          else
            publisher.present? ? publisher.truncate(20, omission: "") : "jsearch"
          end

          employer = item["employer_name"].to_s
          city = item["job_city"].to_s
          state = item["job_state"].to_s
          country = item["job_country"].to_s

          jobs << {
            title: [ title, employer, [ city, state ].compact_blank.join(", ") ].compact_blank.join(" - "),
            company: employer,
            location: [ city, state, country ].compact_blank.join(", "),
            url: apply_link,
            salary: format_salary(item["job_min_salary"], item["job_max_salary"]),
            source: detected_source,
            category: categorize(title, [ item["job_employment_type"].to_s ]),
            description: (item["job_description"] || "").truncate(2000, omission: ""),
            posted_at: item["job_posted_at_datetime_utc"].to_s,
            external_id: "jsearch-#{item['job_id']}"
          }
        end
      end

      # Deduplicate by URL
      jobs.uniq { |j| j[:url] }
    end
  end
end
