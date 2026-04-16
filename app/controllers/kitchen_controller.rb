class KitchenController < ApplicationController
  allow_unauthenticated_access

  def index
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
    else
      @events = []
      @week1_events = @week2_events = @week3_events = @week4_events = []
      @total = 0
      @sold_out = 0
    end
  end
end
