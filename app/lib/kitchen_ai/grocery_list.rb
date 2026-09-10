# Builds (or fetches from cache) the consolidated grocery list for a set of
# KitchenEvents, and the per-week estimated total. Shared by the grocery page,
# the per-class pull sheet, and the week-card total, so they all hit the SAME
# cache key.
#
# Stateless math (tag/headcount/stations/cache_key) lives in class methods; an
# instance memoizes the packets map + observed prices for one request/job, so
# the list page can total every week cheaply.
module KitchenAi
  class GroceryList
    CACHE_TTL  = 14.days

    class << self
      # People to cook for; fall back to 0 so the class still appears (flagged)
      # rather than vanishing. A ticket can cover two people (couples classes),
      # so scale by people_per_ticket or the food is bought for half the room.
      def headcount(event)
        event.tickets_sold.to_i * event.people_per_ticket
      end

      # Station counts per recipe in the packet, for one class: the recipe's
      # own doubles/singles when set on the edit page, else the class's
      # booking-derived default (KitchenEvent#default_station_counts). Doubles
      # cook the full amounts, singles the half amounts; the aggregator buys
      # for both. Returns [ [ recipe_title, StationCounts ], ... ].
      def recipe_stations(event, packet)
        default = event.default_station_counts
        packet.recipes.map { |r| [ r["title"].to_s, KitchenPacket.station_counts_for(r, default: default) ] }
      end

      # Stations physically set up for the class (equipment checklist): the
      # busiest recipe's total, else the booking default.
      def stations(event, packet = nil)
        return event.default_station_counts.total unless packet
        recipe_stations(event, packet).map { |_, sc| sc.total }.max || event.default_station_counts.total
      end

      # "Salmon 4 double; Chicken 2 double, 2 single" for the sheet header and
      # Covers line. A one-recipe packet just gets the plain label.
      def stations_summary(event, packet)
        rs = recipe_stations(event, packet)
        return rs.first&.last&.label.to_s if rs.size <= 1
        rs.map { |title, sc| "#{title} #{sc.short}" }.join("; ")
      end

      # Short, mostly-unique chip label for a class: drop the trailing date and
      # the "Class" filler, collapse junk, then append M/D so two same-named
      # classes in the window stay distinct.
      def tag(event)
        base = event.name.to_s
                    .gsub(%r{\b\d{1,2}/\d{1,2}/\d{2,4}\b}, "")
                    .gsub(/\b(cooking\s+)?class\b/i, "")
                    .gsub(/[^\p{Alpha}\s&':\-]/, " ").squeeze(" ").strip
        base = event.name.to_s.strip if base.blank?
        base = base.truncate(22, separator: " ", omission: "")
        d = event.start_at&.strftime("%-m/%-d")
        d ? "#{base} #{d}" : base
      end

      # Cache key folds in BOTH the recipe set and the observed prices, so a
      # newly uploaded receipt (new or changed prices) rebuilds the list instead
      # of serving a stale estimate.
      def cache_key(with_recipe, observed = {})
        # Exclude equipment from the key: it's the per-station setup gear, which
        # the pull sheet renders live from the packet and which has no bearing
        # on the ingredient/price aggregation. Keeping it here would re-bill Opus
        # every time someone tweaks an equipment tag.
        # Recipe-level station counts ride along in packet data; the booking
        # default (for recipes with none set) is keyed explicitly.
        recipes = with_recipe.sort_by { |c| c[:event].url }
                             .map { |c| [ c[:event].url, c[:tag], c[:default_stations], c[:packet].data.except("equipment") ] }
        payload = { recipes: recipes, observed: observed.sort.to_h }.to_json
        "nyk_grocery_list:v4:#{Digest::SHA256.hexdigest(payload)}"
      end

      # Estimated $ total across a built list's line items, or nil.
      def total_for(result)
        return nil unless result&.ok?
        result.categories.sum { |cat| Array(cat["items"]).sum { |i| i["price"].to_f } }
      end
    end

    def initialize(user: nil)
      @user = user
    end

    # All recipe packets indexed by the event URL they're attached to. Loaded
    # once per instance (the list page reads it for every week's total).
    def packets_by_event_url
      @packets_by_event_url ||=
        KitchenPacket.includes(:links).flat_map { |h| h.links.map { |l| [ l.event_url, h ] } }.to_h
    end

    # Most recent observed unit price per ingredient (from receipts) as a plain
    # hash the aggregator folds into its prompt: { name => {price, unit} }.
    def observed_prices
      @observed_prices ||= IngredientPrice.recent_by_name.transform_values do |ip|
        { "price" => ip.unit_price_dollars, "unit" => ip.unit }
      end
    end

    # Turn events into the aggregator's per-class input: only the ones with a
    # recipe, each tagged and scaled by booked stations. per_ticket /
    # per_ticket_overridden drive the "Ticket portions" control on the list.
    def with_recipe(events)
      packets = packets_by_event_url
      events.filter_map do |e|
        h = packets[e.url] or next
        default = e.default_station_counts
        { event: e, packet: h, tag: self.class.tag(e),
          headcount: self.class.headcount(e), stations: self.class.stations(e, h),
          default_stations: [ default.doubles, default.singles ],
          recipe_stations: self.class.recipe_stations(e, h),
          stations_summary: self.class.stations_summary(e, h),
          per_ticket: e.people_per_ticket, per_ticket_overridden: e.portion_overridden? }
      end
    end

    # Build or fetch the aggregated list for a with_recipe set. Returns
    # [result, from_cache]. write: false reads cache only (never bills Opus) and
    # returns [nil, false] on a miss.
    def fetch(with_recipe, write: true)
      observed = observed_prices
      key = self.class.cache_key(with_recipe, observed)
      if (hit = Rails.cache.read(key))
        return [ hit, true ]
      end
      return [ nil, false ] unless write

      # Each recipe goes to the aggregator with its resolved station counts.
      items = with_recipe.map do |c|
        recipes = c[:packet].recipes.zip(c[:recipe_stations]).map do |r, (_, sc)|
          r.merge("doubles" => sc.doubles, "singles" => sc.singles)
        end
        { class_name: c[:event].name, tag: c[:tag], stations: c[:stations], recipes: recipes }
      end
      result = KitchenAi::GroceryAggregator.new(user: @user).build(items, observed_prices: observed)
      Rails.cache.write(key, result, expires_in: CACHE_TTL) if result&.ok?
      [ result, false ]
    end

    # Read-only estimated $ total for a set of events (one week), or nil if the
    # list isn't cached yet. Never bills Opus.
    def cached_total(events)
      wr = with_recipe(events)
      return nil if wr.empty?
      result, = fetch(wr, write: false)
      self.class.total_for(result)
    end
  end
end
