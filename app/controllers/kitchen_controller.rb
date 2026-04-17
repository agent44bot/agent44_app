class KitchenController < ApplicationController
  allow_unauthenticated_access

  def index
    @admin = false
    load_kitchen_data
    render "admin/kitchen/index", layout: "application"
  end

  private

  def load_kitchen_data
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
