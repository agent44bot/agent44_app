require "test_helper"
require "minitest/mock"

class ScrapeKitchenJobTest < ActiveJob::TestCase
  # Stand-in for NyKitchenScraper. Nothing here touches the network.
  class FakeScraper
    def initialize(events) = @events = events
    def fetch_events(months:) = @events.map(&:dup)
    def fetch_availability(_url) = nil
  end

  def event(name, url: nil)
    { url: url || "https://nykitchen.com/event/#{name.parameterize}",
      name: name, start_at: 3.days.from_now, availability: "InStock" }
  end

  def run_with(events, **opts)
    NyKitchenScraper.stub(:new, FakeScraper.new(events)) { ScrapeKitchenJob.perform_now(**opts) }
  end

  test "skips when today's snapshot already exists" do
    snap = KitchenSnapshot.create!(taken_on: Date.current)
    snap.kitchen_events.create!(event("Knife Skills"))

    run_with([ event("Something Else") ])

    assert_equal [ "Knife Skills" ], snap.reload.kitchen_events.pluck(:name)
  end

  test "force re-scrapes and drops a class that came off the website" do
    snap = KitchenSnapshot.create!(taken_on: Date.current)
    snap.kitchen_events.create!(event("Knife Skills"))
    snap.kitchen_events.create!(event("Cancelled Pop Up"))

    run_with([ event("Knife Skills") ], force: true)

    assert_equal [ "Knife Skills" ], KitchenSnapshot.latest.kitchen_events.pluck(:name),
                 "the pulled class must stop printing on the flyer"
  end

  test "an empty scrape keeps the last good snapshot instead of blanking the schedule" do
    snap = KitchenSnapshot.create!(taken_on: Date.current)
    snap.kitchen_events.create!(event("Knife Skills"))

    run_with([], force: true)

    assert_equal [ "Knife Skills" ], snap.reload.kitchen_events.pluck(:name)
    assert Notification.where(source: "kitchen_scraper", level: "error").exists?,
           "a blocked scrape has to be noisy, not silent"
  end
end
