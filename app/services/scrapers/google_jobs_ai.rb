module Scrapers
  # Variant of GoogleJobs that hunts for "Agent Director"-class roles
  # (the next-gen job described on /lab) instead of QA/SDET roles.
  # Reuses GoogleJobs#call entirely — only the default search terms differ,
  # and those come from the ScraperSource record's search_terms column.
  class GoogleJobsAi < GoogleJobs
  end
end
