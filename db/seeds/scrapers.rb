default_terms = %w[sdet test\ automation qa\ automation quality\ engineer test\ engineer software\ test qa\ engineer]

scrapers = [
  {
    name: "RemoteOK",
    slug: "remoteok",
    source_url: "https://remoteok.com/api?tag=testing",
    schedule: "daily",
    search_terms: default_terms
  },
  {
    name: "Arbeitnow",
    slug: "arbeitnow",
    source_url: "https://www.arbeitnow.com/api/job-board-api",
    schedule: "daily",
    search_terms: default_terms,
    config: { "max_pages" => 3 }
  },
  {
    name: "Jobicy",
    slug: "jobicy",
    source_url: "https://jobicy.com/api/v2/remote-jobs",
    schedule: "daily",
    search_terms: default_terms,
    config: { "tags" => %w[testing automation] }
  },
  {
    name: "Welcome to the Jungle",
    slug: "welcometothejungle",
    source_url: "https://CSEKHVMS53-dsn.algolia.net/1/indexes/wttj_jobs_production_en/query",
    schedule: "daily",
    search_terms: ["SDET", "QA engineer", "test automation", "quality engineer"],
    config: {
      "algolia_app_id" => "CSEKHVMS53",
      "algolia_api_key" => "4bd8f6215d0cc52b26430765769e65a0"
    }
  },
  {
    name: "DevITjobs",
    slug: "devitjobs",
    source_url: "https://devitjobs.com/api/jobsLight?search=QA",
    schedule: "daily",
    search_terms: default_terms
  },
{
    name: "Google Jobs (SerpAPI)",
    slug: "google_jobs",
    api_key_name: "SERPAPI_KEY",
    schedule: "daily",
    search_terms: [
      "SDET software development engineer in test",
      "QA test automation engineer",
      "senior quality engineer automation"
    ]
  }
]

scrapers.each do |attrs|
  ScraperSource.find_or_create_by!(slug: attrs[:slug]) do |s|
    s.assign_attributes(attrs)
  end
end

puts "Seeded #{scrapers.size} scraper sources"
