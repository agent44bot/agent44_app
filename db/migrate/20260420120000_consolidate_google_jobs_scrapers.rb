class ConsolidateGoogleJobsScrapers < ActiveRecord::Migration[8.0]
  def up
    # Merge all Google Jobs variants into a single scraper with combined search terms
    main = ScraperSource.find_by(slug: "google_jobs")
    return unless main

    combined_terms = [
      "SDET software development engineer in test",
      "QA test automation engineer",
      "senior quality engineer automation",
      "security engineer application security",
      "DevSecOps engineer",
      "blockchain security engineer web3",
      "AI agent engineer director",
      "penetration tester pentesting"
    ]

    main.update!(search_terms: combined_terms, schedule: "every_3d")

    # Remove the variant scrapers
    %w[google_jobs_ai google_jobs_security google_jobs_crypto google_jobs_devsecops].each do |slug|
      ScraperSource.find_by(slug: slug)&.destroy
    end
  end

  def down
    # Restore the original google_jobs terms and schedule
    main = ScraperSource.find_by(slug: "google_jobs")
    if main
      main.update!(
        search_terms: [
          "SDET software development engineer in test",
          "QA test automation engineer",
          "senior quality engineer automation"
        ],
        schedule: "daily"
      )
    end
  end
end
