module WorkspacesHelper
  # Section header for a recent post, grouped by its calendar day in the
  # workspace's timezone: "Today", "Yesterday", or a formatted date for
  # anything older (e.g. "Jun 27" this year, "Jun 27, 2025" in prior years).
  def social_post_day_label(time, timezone)
    date  = time.in_time_zone(timezone).to_date
    today = Time.current.in_time_zone(timezone).to_date
    case (today - date).to_i
    when 0 then "Today"
    when 1 then "Yesterday"
    else
      date.year == today.year ? date.strftime("%b %-d") : date.strftime("%b %-d, %Y")
    end
  end
end
