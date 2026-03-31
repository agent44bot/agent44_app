module Scrapers
  class Arbeitnow < Base
    def call
      max_pages = (config["max_pages"] || 3).to_i
      jobs = []

      (1..max_pages).each do |page|
        data = fetch_json("https://www.arbeitnow.com/api/job-board-api?page=#{page}")
        break unless data&.dig("data")

        data["data"].each do |item|
          next unless relevant?(item["title"].to_s, item["tags"])

          posted_at = item["created_at"].present? ? Time.at(item["created_at"]).utc.iso8601 : ""

          jobs << {
            title: item["title"],
            company: item["company_name"].to_s,
            location: item["location"].to_s,
            url: item["url"].to_s,
            salary: "",
            source: "arbeitnow",
            category: categorize(item["title"], item["tags"]),
            description: item["description"].to_s,
            posted_at: posted_at,
            external_id: "arbeitnow-#{item['slug']}"
          }
        end
      end

      jobs
    end
  end
end
