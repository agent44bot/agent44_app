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

  # Inline SVG QR code for print (no network call, scales via CSS). Used on the
  # printable class schedule so walk-ins can scan straight to the reserve page.
  def qr_svg(data)
    svg = RQRCode::QRCode.new(data.to_s).as_svg(
      use_path: true, viewbox: true, standalone: true, color: "000"
    )
    svg.sub(/\A<\?xml.*?\?>/m, "").html_safe
  end

  # Pull a one-line human blurb out of a scraped class description. The scrape
  # prefixes the real text with a (sometimes character-mangled) title + a
  # date/time header, so we drop everything up to the time range and return a
  # clean, truncated snippet. Falls back to the whole cleaned text if no time
  # range is found. Returns "" when there's nothing usable.
  def class_blurb(description, length: 160)
    clean = CGI.unescapeHTML(strip_tags(description.to_s)).gsub(/\p{Space}+/, " ").strip
    return "" if clean.blank?
    after = clean.split(/\d{1,2}:\d{2}\s*[ap]m\s*[-–]\s*\d{1,2}:\d{2}\s*[ap]m/i).last.to_s.strip
    blurb = after.length >= 20 ? after : clean
    truncate(blurb, length: length, separator: " ")
  end

  # Time-of-day greeting for the Super Agent hub card, computed in Eastern time
  # (Lora, RB, and NYK are all Eastern). Keeps the "personal briefing" feel
  # without the hardcoded "morning" reading wrong in the afternoon.
  def nyk_time_greeting(now = Time.current)
    case now.in_time_zone("Eastern Time (US & Canada)").hour
    when 5..11  then "☀️ This morning:"
    when 12..16 then "🌤️ This afternoon:"
    when 17..21 then "🌆 This evening:"
    else             "🌙 Tonight:"
    end
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
