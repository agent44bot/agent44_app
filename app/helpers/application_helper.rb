module ApplicationHelper
  SOURCE_LABELS = {
    "remoteok" => "RemoteOK",
    "arbeitnow" => "Arbeitnow",
    "jobicy" => "Jobicy",
    "welcometothejungle" => "WTTJ",
    "linkedin" => "LinkedIn",
    "indeed" => "Indeed",
    "glassdoor" => "Glassdoor",
    "google_jobs" => "Google Jobs",
    "jsearch" => "JSearch",
    "devitjobs" => "DevITjobs",
    "bitcoinjobs" => "BitcoinJobs",
    "bitcoinerjobs" => "BitcoinerJobs",
    "bitcoin_bamboohr" => "Bitcoin.com",
    "qajobboard" => "QA Job Board",
    "ziprecruiter" => "ZipRecruiter",
    "dice" => "Dice",
    "monster" => "Monster",
    "simplyhired" => "SimplyHired",
    "jobilize" => "Jobilize",
    "lensa" => "Lensa",
    "learn4good" => "Learn4Good",
    "adzuna" => "Adzuna",
    "jooble" => "Jooble",
    "jobleads" => "JobLeads",
    "talent.com" => "Talent.com",
    "weworkremotely" => "WeWorkRemotely",
    "usajobs" => "USAJobs",
    "teal" => "Teal",
    "ladders" => "Ladders",
    "himalayas" => "Himalayas"
  }.freeze

  def source_label(source)
    SOURCE_LABELS[source] || source&.titleize
  end

  def days_ago_in_words(date)
    return "recently" if date.nil?

    days = (Time.current.to_date - date.to_date).to_i

    case days
    when ..0 then "today"
    when 1 then "1 day ago"
    else "#{days} days ago"
    end
  end
end
