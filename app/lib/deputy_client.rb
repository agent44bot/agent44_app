require "net/http"
require "json"

# Read-only client for the Deputy.com scheduling API. Powers the NY Kitchen
# "Team hours" page (kitchen#hours): pulls a week of rostered (scheduled) shifts
# and totals hours per employee.
#
# Config comes from ENV first, then Rails credentials (dig :deputy, ...), then a
# hardcoded install default. Like the other external clients (ApnsPusher,
# TelegramNotifier), it no-ops gracefully when unconfigured rather than raising
# at boot: callers check `configured?` and fall back to a friendly message.
#
# These are SCHEDULED hours (the Roster resource), matching Deputy's schedule
# panel. Swap the resource to Timesheet for clocked/approved hours.
class DeputyClient
  class Error < StandardError; end

  def self.install
    ENV["DEPUTY_INSTALL"].presence ||
      Rails.application.credentials.dig(:deputy, :install) ||
      "9bd0e317083439"
  end

  def self.geo
    ENV["DEPUTY_GEO"].presence || Rails.application.credentials.dig(:deputy, :geo) || "na"
  end

  def self.token
    ENV["DEPUTY_API_TOKEN"].presence || Rails.application.credentials.dig(:deputy, :api_token)
  end

  def self.configured?
    token.present?
  end

  # Scheduled hours for the inclusive Date range [from, to]. Returns:
  #   { rows: [{ employee:, hours: }], total:, open_hours:, by_area: {name=>hrs}, shift_count: }
  # rows are staffed employees (highest hours first); open/unfilled shifts
  # (Employee 0, no assignee) are summed separately into open_hours so they
  # never masquerade as a person on the payroll list.
  def self.weekly_hours(from, to)
    employees   = Hash.new(0.0)
    areas       = Hash.new(0.0)
    open_hours  = 0.0
    shift_count = 0

    query_roster(from, to).each do |r|
      st, et = r["StartTime"], r["EndTime"]
      next unless st.is_a?(Numeric) && et.is_a?(Numeric) && et > st

      hours = (et - st) / 3600.0
      shift_count += 1

      area = r.dig("OperationalUnitObject", "OperationalUnitName").to_s
      areas[area] += hours if area.present?

      name = r.dig("EmployeeObject", "DisplayName").to_s.strip
      if name.blank? || r["Employee"].to_i.zero?
        open_hours += hours
      else
        employees[name] += hours
      end
    end

    {
      rows:        employees.map { |n, h| { employee: n, hours: h.round(2) } }
                            .sort_by { |x| [ -x[:hours], x[:employee] ] },
      total:       employees.values.sum.round(2),
      open_hours:  open_hours.round(2),
      by_area:     areas.sort_by { |_, v| -v }.map { |a, v| [ a, v.round(2) ] }.to_h,
      shift_count: shift_count
    }
  end

  def self.query_roster(from, to)
    body = {
      search: {
        s1: { field: "Date", type: "ge", data: from.to_s },
        s2: { field: "Date", type: "le", data: to.to_s }
      },
      join: %w[OperationalUnitObject EmployeeObject],
      max: 500
    }
    resp = post("resource/Roster/QUERY", body)
    raise Error, "unexpected Deputy response shape" unless resp.is_a?(Array)
    resp
  end

  def self.post(path, body)
    raise Error, "Deputy API token not configured" unless configured?

    uri = URI("https://#{install}.#{geo}.deputy.com/api/v1/#{path}")
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{token}"
    req["Content-Type"]  = "application/json"
    req.body = body.to_json

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 25) do |http|
      http.request(req)
    end
    raise Error, "Deputy API #{res.code}: #{res.body.to_s[0, 300]}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  end
end
