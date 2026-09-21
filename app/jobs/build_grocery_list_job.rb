# Builds and caches the aggregated grocery list off the web request, so the
# grocery page returns immediately and its frame polls until the list is ready
# (the aggregation is a slow, paid Claude call). Reconstructs the same event set
# the page did (by scope), so it writes the exact cache key the page then reads.
#
# scope is { "event_url" => url } for a single-class pull sheet, else
# { "from" => "YYYY-MM-DD", "to" => "YYYY-MM-DD" } for a date window.
class BuildGroceryListJob < ApplicationJob
  queue_as :extraction # shares the one-at-a-time AI queue

  def perform(scope, user_id = nil)
    svc    = KitchenAi::GroceryList.new(user: User.find_by(id: user_id))
    events = select_events(KitchenSnapshot.latest, scope)
    wr     = svc.with_recipe(events)
    return if wr.empty?

    key    = KitchenAi::GroceryList.cache_key(wr, svc.observed_prices)
    marker = "#{key}:building"

    # The Claude call touches no primary DB; hand the connection back for it.
    ActiveRecord::Base.connection_pool.release_connection
    result, = svc.fetch(wr, write: true) # builds + caches (skips if another run already did)
    # Flip the navbar build bar to its "ready" (or "failed") state.
    GroceryBuildStatus.finish(user_id: user_id, token: key,
                              status: result&.ok? ? "ready" : "failed",
                              error: (result&.error unless result&.ok?))
  ensure
    Rails.cache.delete(marker) if marker
  end

  private

  def select_events(snapshot, scope)
    url = scope["event_url"]
    # A hand-added class (private booking, camp) is keyed "manual-<id>" and
    # lives outside the snapshot, so it resolves from its own table. It can also
    # be the only class there is, which is why a missing snapshot no longer ends
    # the job.
    if KitchenManualClass.packet_url?(url)
      id = KitchenManualClass.id_from_packet_url(url)
      return [ id && KitchenManualClass.find_by(id: id) ].compact
    end
    return [] unless snapshot

    events = snapshot.kitchen_events.upcoming
    if url.present?
      events.select { |e| e.url == url }
    else
      from = Date.parse(scope["from"].to_s)
      to   = Date.parse(scope["to"].to_s)
      range = from..to
      events.select { |e| range.cover?(e.start_at.to_date) }
    end.sort_by(&:start_at)
  rescue ArgumentError, TypeError
    []
  end
end
