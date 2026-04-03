module Scrapers
  class Remoteok < Base
    def call
      data = fetch_json(source.source_url.presence || "https://remoteok.com/api?tag=testing")
      return [] unless data.is_a?(Array)

      data.filter_map do |item|
        next unless item.is_a?(Hash) && item["position"].present?
        next unless relevant?(item["position"], item["tags"])

        {
          title: item["position"],
          company: item["company"].to_s,
          location: item["location"].presence || "Remote",
          url: item["url"].presence || "https://remoteok.com/l/#{item['id']}",
          salary: format_salary(item["salary_min"], item["salary_max"]),
          source: "remoteok",
          category: categorize(item["position"], item["tags"]),
          ai_augmented: ai_augmented?(item["position"], item["tags"]),
          description: item["description"].to_s,
          posted_at: item["date"].to_s,
          external_id: "remoteok-#{item['id']}"
        }
      end
    end
  end
end
