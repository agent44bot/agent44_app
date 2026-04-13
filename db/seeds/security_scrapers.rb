security_scrapers = [
  {
    name: "Google Jobs (Security)",
    slug: "google_jobs_security",
    api_key_name: "SERPAPI_KEY",
    schedule: "daily",
    search_terms: [
      "security engineer application security",
      "penetration tester pentesting",
      "cryptography engineer",
      "zero trust security engineer"
    ]
  },
  {
    name: "Google Jobs (Crypto/Web3)",
    slug: "google_jobs_crypto",
    api_key_name: "SERPAPI_KEY",
    schedule: "daily",
    search_terms: [
      "blockchain security engineer",
      "smart contract auditor",
      "web3 security engineer",
      "bitcoin engineer developer"
    ]
  },
  {
    name: "Google Jobs (DevSecOps)",
    slug: "google_jobs_devsecops",
    api_key_name: "SERPAPI_KEY",
    schedule: "daily",
    search_terms: [
      "DevSecOps engineer",
      "security automation engineer",
      "application security testing SAST DAST",
      "identity access management engineer"
    ]
  }
]

created = 0
security_scrapers.each do |attrs|
  scraper = ScraperSource.find_or_initialize_by(slug: attrs[:slug])
  if scraper.new_record?
    scraper.assign_attributes(attrs)
    created += 1 if scraper.save
  end
end

puts "Seeded #{created} security scraper sources (#{security_scrapers.size - created} already existed)"
