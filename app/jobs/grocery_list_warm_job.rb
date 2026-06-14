# Warms the cached grocery list for a week so the orange "Grocery list" card on
# Sam's list can show the estimated total without anyone first opening the
# grocery page. Enqueued from the list render for any week that has recipes but
# no cached list yet (KitchenAi::GroceryList#warm_async dedups). Idempotent: if
# the list is already cached it returns without re-billing Opus.
class GroceryListWarmJob < ApplicationJob
  queue_as :default

  def perform(from, to)
    snapshot = KitchenSnapshot.latest
    return unless snapshot

    range  = from.to_date..to.to_date
    events = snapshot.kitchen_events.upcoming.select { |e| range.cover?(e.start_at.to_date) }
    svc    = KitchenAi::GroceryList.new
    with_recipe = svc.with_recipe(events)
    return if with_recipe.empty?

    svc.fetch(with_recipe, write: true) # builds + caches if not already cached
  end
end
