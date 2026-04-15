class KitchenController < ApplicationController
  allow_unauthenticated_access

  def index
    snapshot = KitchenSnapshot.latest
    if snapshot
      @events = snapshot.kitchen_events.upcoming
      @today_events    = @events.select { |e| e.start_at.to_date == Date.today }
      @tomorrow_events = @events.select { |e| e.start_at.to_date == Date.today + 1 }
      @week_events     = @events.select { |e| (Date.today + 2..Date.today + 14).cover?(e.start_at.to_date) }
      @total = @events.size
      @sold_out = @events.count(&:sold_out?)
      @last_updated = snapshot.taken_on
    else
      @events = []
      @today_events = []
      @tomorrow_events = []
      @week_events = []
      @total = 0
      @sold_out = 0
    end
  end
end
