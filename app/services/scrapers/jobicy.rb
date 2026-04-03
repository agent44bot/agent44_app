module Scrapers
  class Jobicy < Base
    TAGS = %w[testing automation].freeze

    def call
      tags = config["tags"] || TAGS
      seen_ids = Set.new
      all_items = []

      tags.each do |tag|
        data = fetch_json("https://jobicy.com/api/v2/remote-jobs?count=50&tag=#{tag}")
        next unless data&.dig("jobs")

        data["jobs"].each do |item|
          item_id = item["id"].to_s
          next if seen_ids.include?(item_id)
          seen_ids.add(item_id)
          all_items << item
        end
      end

      all_items.filter_map do |item|
        next unless relevant?(item["jobTitle"].to_s, [ item["jobIndustry"].to_s ])

        {
          title: item["jobTitle"],
          company: item["companyName"].to_s,
          location: item["jobGeo"].presence || "Remote",
          url: item["url"].to_s,
          salary: format_salary(item["annualSalaryMin"], item["annualSalaryMax"]),
          source: "jobicy",
          category: categorize(item["jobTitle"], [ item["jobType"].to_s ]),
          ai_augmented: ai_augmented?(item["jobTitle"], [ item["jobType"].to_s ]),
          description: item["jobDescription"].to_s,
          posted_at: item["pubDate"].to_s,
          external_id: "jobicy-#{item['id']}"
        }
      end
    end
  end
end
