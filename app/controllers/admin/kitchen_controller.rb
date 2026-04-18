module Admin
  class KitchenController < BaseController
    def trigger_smoke
      token = ENV["GITHUB_PAT"]
      if token.blank?
        redirect_to admin_kitchen_path, alert: "GITHUB_PAT not configured"
        return
      end

      uri = URI("https://api.github.com/repos/agent44bot/agent44_app/dispatches")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Accept"] = "application/vnd.github+json"
      req["Content-Type"] = "application/json"
      req.body = { event_type: "smoke-nyk" }.to_json

      res = http.request(req)

      if res.is_a?(Net::HTTPSuccess) || res.code == "204"
        redirect_to admin_kitchen_path, notice: "Smoke test triggered — results will appear shortly"
      else
        redirect_to admin_kitchen_path, alert: "GitHub dispatch failed (#{res.code})"
      end
    rescue => e
      redirect_to admin_kitchen_path, alert: "Error: #{e.message}"
    end

    def index
      @admin = true
      snapshot = KitchenSnapshot.latest
      if snapshot
        @events = snapshot.kitchen_events.upcoming
        today = Date.today
        @week1_events = @events.select { |e| (today..today + 6).cover?(e.start_at.to_date) }
        @week2_events = @events.select { |e| (today + 7..today + 13).cover?(e.start_at.to_date) }
        @week3_events = @events.select { |e| (today + 14..today + 20).cover?(e.start_at.to_date) }
        @week4_events = @events.select { |e| (today + 21..today + 27).cover?(e.start_at.to_date) }
        @total = @events.size
        @sold_out = @events.count(&:sold_out?)
        @last_updated = snapshot.taken_on

        list_events = @week1_events + @week2_events + @week3_events + @week4_events
        statuses = list_events.map(&:availability_status)
        @filter_counts = {
          "all"     => statuses.size,
          "instock" => statuses.count("instock"),
          "limited" => statuses.count("limited"),
          "soldout" => statuses.count("soldout"),
          "closed"  => statuses.count("closed")
        }
      else
        @events = []
        @week1_events = @week2_events = @week3_events = @week4_events = []
        @total = 0
        @sold_out = 0
        @filter_counts = { "all" => 0, "instock" => 0, "limited" => 0, "soldout" => 0, "closed" => 0 }
      end

      @smoke_runs = SmokeTestRun.for_name("nyk_calendar_nav").recent.with_attached_video.with_attached_thumbnail.limit(20)
    end
  end
end
