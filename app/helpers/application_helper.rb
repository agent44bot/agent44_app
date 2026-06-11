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

  # NY Kitchen "Field Roster" identity per agent kind: codename callsign,
  # classification tag, accent colour, emoji. The hub cards AND the agent
  # detail-page headers both read this so the naming can't drift. A saved
  # display_name (the rename feature) overrides the default callsign.
  NYK_ROSTER = {
    "ask"     => { call: "Carson", tag: "Concierge", accent: "#f97316", emoji: "💬" },
    "list"    => { call: "Sam",   tag: "Scheduler", accent: "#38bdf8", emoji: "📋" },
    "analyst" => { call: "Iris",  tag: "Analyst",   accent: "#34d399", emoji: "📊" },
    "social"  => { call: "Echo",  tag: "Broadcast", accent: "#a78bfa", emoji: "📣" },
    "display" => { call: "Neon",  tag: "Marquee",   accent: "#fbbf24", emoji: "🖥" },
    "data"    => { call: "Scout", tag: "Recon",     accent: "#fb7185", emoji: "🕷️" },
    "test"    => { call: "Argus", tag: "Sentry",    accent: "#22d3ee", emoji: "🔁" }
  }.freeze

  def nyk_agent_meta(kind)
    NYK_ROSTER[kind.to_s] || { call: kind.to_s.titleize, tag: "Agent", accent: "#f97316", emoji: "🤖" }
  end

  # An agent's display callsign: its saved display_name if set, else the roster
  # default. `agent` may be nil (anonymous viewer with no workspace yet).
  def nyk_agent_callsign(kind, agent = nil)
    agent&.display_name.presence || nyk_agent_meta(kind)[:call]
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
