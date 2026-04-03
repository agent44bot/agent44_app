module Scrapers
  class Devitjobs < Base
    def call
      data = fetch_json(source.source_url.presence || "https://devitjobs.com/api/jobsLight?search=QA")
      return [] unless data.is_a?(Array)

      seen_ids = Set.new
      data.filter_map do |item|
        obj_id = item["_id"].to_s
        next if seen_ids.include?(obj_id)
        seen_ids.add(obj_id)

        name = item["name"].to_s
        next unless relevant?(name, item["filterTags"])

        city = (item["cityCategory"] || "").tr("-", " ")
        state = (item["stateCategory"] || "").tr("-", " ")
        location = [ city, state ].compact_blank.join(", ")

        job_slug = item["jobUrl"].to_s
        url = job_slug.present? ? "https://devitjobs.com/job/#{job_slug}" : ""

        {
          title: name,
          company: item["company"].to_s,
          location: location,
          url: url,
          salary: format_salary(item["annualSalaryFrom"], item["annualSalaryTo"]),
          source: "devitjobs",
          category: categorize(name, item["filterTags"]),
          ai_augmented: ai_augmented?(name, item["filterTags"]),
          description: "",
          posted_at: item["activeFrom"].to_s,
          external_id: "devitjobs-#{obj_id}"
        }
      end
    end
  end
end
