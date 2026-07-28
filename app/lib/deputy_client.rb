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

  # Deep link to Deputy's Approve Timesheets screen. It's a SPA, so we can't
  # target a specific week/location in the URL; Lora sets those in Deputy.
  def self.approve_url
    "https://#{install}.#{geo}.deputy.com/#/approve-v2"
  end

  # Active, REAL timesheets whose Date falls in [from, to], with the employee
  # joined. "Real" excludes the 0-minute ghost entries (start == end, TotalTime
  # 0) that accumulate in Deputy from stray clock-ins, so they never inflate
  # counts or pollute status.
  def self.query_timesheets(from, to)
    resp = post("resource/Timesheet/QUERY", {
      search: { s1: { field: "Date", type: "ge", data: from.to_s },
                s2: { field: "Date", type: "le", data: to.to_s } },
      join: %w[EmployeeObject],
      max: 500
    })
    return [] unless resp.is_a?(Array)
    resp.select { |t| t.is_a?(Hash) && !t["Discarded"] && t["TotalTime"].to_f.positive? }
  end

  # Count of active, real timesheets for the week (drives Generate vs Review).
  def self.active_timesheet_count(from, to)
    query_timesheets(from, to).size
  end

  # Per-employee approval status for the week (ghosts excluded). Returns:
  #   { by_employee: { "Allyn Itterly" => { approved:, pending:, total: }, ... },
  #     total:, approved:, pending: }
  def self.timesheet_status(from, to)
    by = Hash.new { |h, k| h[k] = { approved: 0, pending: 0 } }
    query_timesheets(from, to).each do |t|
      name = t.dig("EmployeeObject", "DisplayName").to_s.strip
      next if name.blank?
      by[name][t["TimeApproved"] ? :approved : :pending] += 1
    end
    approved = by.values.sum { |v| v[:approved] }
    pending  = by.values.sum { |v| v[:pending] }
    {
      by_employee: by.transform_values { |v| v.merge(total: v[:approved] + v[:pending]) },
      total:    approved + pending,
      approved: approved,
      pending:  pending
    }
  end

  # Create one UNAPPROVED timesheet per staffed scheduled shift in [from, to].
  #
  # Idempotency guard: if ANY active timesheet already exists for the week, it
  # creates nothing and returns { status: :exists, existing: N } so the caller
  # shows a "review in Deputy" link instead of ever risking duplicates.
  #
  # This never touches the roster: it READS shifts (Roster/QUERY) and WRITES
  # only Timesheet records (a separate resource). Open/unfilled shifts are
  # skipped (no employee to bill).
  def self.generate_week_timesheets(from, to)
    existing = active_timesheet_count(from, to)
    return { status: :exists, existing: existing } if existing.positive?

    staffed = query_roster(from, to).select do |r|
      r["Employee"].to_i.positive? && r["StartTime"].is_a?(Numeric) &&
        r["EndTime"].is_a?(Numeric) && r["EndTime"] > r["StartTime"] && !r["Open"]
    end

    created = 0
    staffed.each do |r|
      resp = post("supervise/timesheet/update", {
        intEmployeeId:     r["Employee"],
        intOpunitId:       r["OperationalUnit"],
        intStartTimestamp: r["StartTime"],
        intEndTimestamp:   r["EndTime"],
        arrSlots:          []
      })
      created += 1 if resp.is_a?(Hash) && resp["Id"]
    rescue Error => e
      Rails.logger.warn("Deputy timesheet create failed for roster #{r['Id']}: #{e.message}")
    end

    { status: :created, created: created, attempted: staffed.size }
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
