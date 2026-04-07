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

  def markdown_to_html(text)
    html = text.dup
    # Convert markdown links [text](url) to HTML with orange styling
    html.gsub!(/\[([^\]]+)\]\(([^)\s]+)\)?/, '<a href="\2" target="_blank" rel="noopener noreferrer" class="text-orange-400 hover:text-orange-300 underline decoration-orange-400/30 hover:decoration-orange-400 transition">\1</a>')
    # Convert **bold** to <strong>
    html.gsub!(/\*\*([^*]+)\*\*/, '<strong class="text-white font-semibold">\1</strong>')
    # Convert bullet lines to list items
    lines = html.split("\n").map(&:strip).reject(&:blank?)
    items = lines.map { |l| l.sub(/^[-*]\s*/, "") }
    "<ul class=\"space-y-3\">#{items.map { |i| "<li class=\"flex gap-3 text-sm text-gray-300 leading-relaxed\"><span class=\"text-orange-500 mt-1 flex-shrink-0\">&#x2022;</span><span class=\"min-w-0 break-words\">#{i}</span></li>" }.join}</ul>"
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
