# Builds (or fetches from cache) the consolidated grocery list for a set of
# KitchenEvents, and the per-week estimated total. Shared by the grocery page,
# the per-class pull sheet, the week-card total, and the background warm job
# (GroceryListWarmJob) so they all hit the SAME cache key.
#
# Stateless math (tag/headcount/stations/cache_key) lives in class methods; an
# instance memoizes the handouts map + observed prices for one request/job, so
# the list page can total every week cheaply.
module KitchenAi
  class GroceryList
    CACHE_TTL  = 14.days
    # How long an enqueued warm "holds the slot" so concurrent list loads don't
    # pile up duplicate jobs (and double-bill Opus) before the first finishes.
    WARM_LOCK_TTL = 10.minutes

    class << self
      # People to cook for; fall back to 0 so the class still appears (flagged)
      # rather than vanishing. A ticket can cover two people (couples classes),
      # so scale by people_per_ticket or the food is bought for half the room.
      def headcount(event)
        event.tickets_sold.to_i * event.people_per_ticket
      end

      # Hands-On stations are ~2 people each, and recipe station_qty is per
      # station. Round up so a half-full station still gets bought for; at least
      # 1 so a booked class always contributes.
      def stations(event)
        [ (headcount(event) / 2.0).ceil, 1 ].max
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
        # the pull sheet renders live from the handout and which has no bearing
        # on the ingredient/price aggregation. Keeping it here would re-bill Opus
        # every time someone tweaks an equipment tag.
        recipes = with_recipe.sort_by { |c| c[:event].url }
                             .map { |c| [ c[:event].url, c[:tag], c[:stations], c[:handout].data.except("equipment") ] }
        payload = { recipes: recipes, observed: observed.sort.to_h }.to_json
        "nyk_grocery_list:v3:#{Digest::SHA256.hexdigest(payload)}"
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

    # All recipe handouts indexed by the event URL they're attached to. Loaded
    # once per instance (the list page reads it for every week's total).
    def handouts_by_event_url
      @handouts_by_event_url ||=
        KitchenHandout.includes(:links).flat_map { |h| h.links.map { |l| [ l.event_url, h ] } }.to_h
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
      handouts = handouts_by_event_url
      events.filter_map do |e|
        h = handouts[e.url] or next
        { event: e, handout: h, tag: self.class.tag(e),
          headcount: self.class.headcount(e), stations: self.class.stations(e),
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

      items = with_recipe.map { |c| { class_name: c[:event].name, tag: c[:tag], stations: c[:stations], recipes: c[:handout].recipes } }
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

    # Enqueue a background warm for this recipe set unless one is already queued
    # (a short-lived lock keyed by the cache key dedups concurrent list loads).
    # No-op for an empty set. Returns true if a job was enqueued.
    def warm_async(from, to, with_recipe)
      return false if with_recipe.empty?
      lock = "#{self.class.cache_key(with_recipe, observed_prices)}:warming"
      return false unless Rails.cache.write(lock, true, expires_in: WARM_LOCK_TTL, unless_exist: true)
      GroceryListWarmJob.perform_later(from.to_s, to.to_s)
      true
    end
  end
end
