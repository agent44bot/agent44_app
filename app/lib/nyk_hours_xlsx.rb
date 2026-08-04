require "caxlsx"

# Builds the "Export to Excel" file for the NY Kitchen team-hours page. Mirrors
# the KitchenGroceryXlsx pattern: initialize with the week + the DeputyClient
# result hash, call #render for the xlsx bytes to send_data.
class NykHoursXlsx
  CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

  def initialize(week_start:, week_end:, data:)
    @week_start = week_start
    @week_end   = week_end
    @data       = data
  end

  def render
    package = Axlsx::Package.new
    wb = package.workbook

    title = wb.styles.add_style(b: true, sz: 14)
    sub   = wb.styles.add_style(i: true, fg_color: "FF808080")
    hdr   = wb.styles.add_style(b: true, bg_color: "FFF0F0F0", border: { style: :thin, color: "FFCCCCCC" })
    cell  = wb.styles.add_style(border: { style: :thin, color: "FFEEEEEE" })
    num   = wb.styles.add_style(border: { style: :thin, color: "FFEEEEEE" }, num_fmt: 2)
    tot   = wb.styles.add_style(b: true, bg_color: "FFF0F0F0", border: { style: :thin, color: "FFCCCCCC" })
    totn  = wb.styles.add_style(b: true, bg_color: "FFF0F0F0", border: { style: :thin, color: "FFCCCCCC" }, num_fmt: 2)

    wb.add_worksheet(name: "Team hours") do |sheet|
      sheet.add_row [ "NY Kitchen team hours (scheduled)" ], style: title
      sheet.add_row [ "Week of #{@week_start.strftime('%a %b %-d')} to #{@week_end.strftime('%a %b %-d, %Y')}" ], style: sub
      sheet.add_row []
      sheet.add_row [ "First name", "Last name", "Hours (h:m)", "Hours (decimal)" ], style: hdr
      # Rows arrive already sorted the way the page is sorted, so the download
      # matches what's on screen.
      @data[:rows].each do |r|
        first, last = EmployeeName.split(r[:employee])
        sheet.add_row [ first, last, self.class.hm(r[:hours]), r[:hours] ], style: [ cell, cell, cell, num ]
      end
      sheet.add_row [ "TOTAL (#{@data[:rows].size} staff)", nil, self.class.hm(@data[:total]), @data[:total] ],
                    style: [ tot, tot, tot, totn ]
      if @data[:open_hours].to_f.positive?
        sheet.add_row []
        sheet.add_row [ "Unfilled open shifts (not staffed)", nil, self.class.hm(@data[:open_hours]), @data[:open_hours] ],
                      style: [ sub, sub, sub, sub ]
      end
      sheet.column_widths 22, 22, 14, 16
    end

    package.to_stream.read
  end

  # Decimal hours -> "Hh MMm".
  def self.hm(hours)
    h = hours.to_i
    m = ((hours - h) * 60).round
    if m == 60
      h += 1
      m = 0
    end
    format("%dh %02dm", h, m)
  end
end
