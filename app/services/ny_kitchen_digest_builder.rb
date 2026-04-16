class NyKitchenDigestBuilder
  # Compares current events against a previous snapshot and returns a digest hash
  # with today/tomorrow/week events and diffs (newly sold out, added, removed, price changes).
  def self.build(current:, previous_snapshot:, today: Date.today)
    cur  = index(current)
    prev = previous_snapshot ? index_snapshot(previous_snapshot) : {}

    sold_out_now   = cur.values.select { |e| sold_out?(e[:availability]) }
    newly_sold_out = sold_out_now.reject { |e| prev[e[:url]] && sold_out?(prev[e[:url]][:availability]) }
    newly_added    = cur.values.reject { |e| prev.key?(e[:url]) }
    removed        = prev.values.reject { |e| cur.key?(e[:url]) }
    price_changes  = cur.values.select { |e| prev[e[:url]] && prev[e[:url]][:price] != e[:price] && prev[e[:url]][:price] }

    upcoming = cur.values.select { |e| e[:start_at] >= Time.current }.sort_by { |e| e[:start_at] }
    week1 = upcoming.select { |e| (today..today + 6).cover?(e[:start_at].to_date) }
    week2 = upcoming.select { |e| (today + 7..today + 13).cover?(e[:start_at].to_date) }
    week3 = upcoming.select { |e| (today + 14..today + 20).cover?(e[:start_at].to_date) }
    week4 = upcoming.select { |e| (today + 21..today + 27).cover?(e[:start_at].to_date) }

    {
      today: today,
      week1_events: week1,
      week2_events: week2,
      week3_events: week3,
      week4_events: week4,
      newly_sold_out: newly_sold_out,
      newly_added: newly_added,
      removed: removed,
      price_changes: price_changes,
      total_upcoming: upcoming.size,
      total_sold_out: sold_out_now.size,
    }
  end

  def self.sold_out?(av)
    d = av.to_s.downcase
    d.include?("soldout") || d.include?("closed")
  end

  def self.index(events)
    events.each_with_object({}) do |e, h|
      h[e[:url]] = e if e[:url]
    end
  end

  # Convert KitchenEvent records from a snapshot into the same hash format
  def self.index_snapshot(snapshot)
    snapshot.kitchen_events.each_with_object({}) do |e, h|
      h[e.url] = {
        url: e.url,
        name: e.name,
        start_at: e.start_at,
        availability: e.availability,
        price: e.price,
        last_known_spots_left: e.last_known_spots_left,
        last_known_capacity: e.last_known_capacity,
      }
    end
  end
end
