module ApplicationHelper
  # The standard "← Back to X" control: an orange button with white text,
  # right-aligned by its caller (wrap in `flex justify-end`). Matches the
  # workspace header buttons so every back link looks the same. Pass the arrow
  # in the label, e.g. back_button("← Back to Sam's list", nyk_list_path).
  BACK_BUTTON_CLASSES =
    "inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-orange-600 " \
    "hover:bg-orange-500 text-white text-sm font-semibold transition".freeze

  def back_button(label, path)
    link_to label, path, class: BACK_BUTTON_CLASSES
  end

  # Renders a user's round avatar: the uploaded photo if present, otherwise a
  # colored initials circle. `size` is the Tailwind h/w pair (e.g. "h-9 w-9")
  # and `ring` the separator ring (defaults to the gray-950 page bg used in
  # overlapping stacks). Pass ring: "" to drop it.
  def user_avatar_tag(user, size: "h-9 w-9", ring: "ring-2 ring-gray-950", extra: "")
    base = "#{size} rounded-full shrink-0 #{ring} #{extra}".strip
    if user.avatar.attached?
      image_tag user.avatar_display, alt: user.display_identifier, loading: "lazy",
                class: "#{base} object-cover bg-gray-800"
    else
      content_tag :span, user.avatar_initials,
        class: "#{base} #{user.avatar_color_classes} inline-flex items-center justify-center " \
               "text-xs font-semibold uppercase select-none leading-none",
        title: user.display_identifier
    end
  end

  # Returns the path only if it's a safe SAME-ORIGIN path (a single leading
  # "/", not "//" or "/\" which browsers treat as protocol-relative / a host).
  # Used to honor a ?return_to= without opening a redirect to another site.
  # nil otherwise, so callers fall back to a default destination.
  def safe_internal_path(path)
    p = path.to_s
    return nil unless p.start_with?("/")
    return nil if p.start_with?("//", "/\\")
    p
  end

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
