# Splits a Deputy DisplayName ("Cynthia S Clinton") into first + last name for
# the team-hours table and its Excel export. Deputy only gives us one display
# string, so we take the last whitespace-separated token as the last name and
# everything before it as the first name (middle names/initials stay with the
# first name). A one-word name ("Elisha") has no last name.
module EmployeeName
  def self.split(display_name)
    parts = display_name.to_s.strip.split(/\s+/)
    return [ "", "" ] if parts.empty?
    return [ parts.first, "" ] if parts.size == 1

    [ parts[0..-2].join(" "), parts.last ]
  end

  def self.first(display_name)
    split(display_name)[0]
  end

  def self.last(display_name)
    split(display_name)[1]
  end

  # Alphabetical key for "sort by last name": people with one name sort by that
  # name, and the first name breaks ties between two Smiths.
  def self.last_first_key(display_name)
    f, l = split(display_name)
    [ (l.presence || f).downcase, f.downcase ]
  end

  # Alphabetical key for "sort by first name".
  def self.first_last_key(display_name)
    f, l = split(display_name)
    [ f.downcase, l.downcase ]
  end
end
