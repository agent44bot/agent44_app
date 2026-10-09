# Builds a recipe packet from an uploaded source in the background so the upload
# returns instantly and the user can roam the app while a navbar bar tracks
# progress. Walks the packet through build_stage reading -> recipes -> equipment
# -> ready, so the bar can show what it is doing, then leaves a "ready" packet
# (or "failed" with the error).
#
# Prod safety: the app runs SolidQueue inside puma sharing a small primary DB
# connection pool with web serving, and each of the two Opus calls takes ~a
# minute. So (1) this runs one-at-a-time (limits_concurrency), and (2) it hands
# its DB connection back to the pool while each API call is in flight
# (with_released_connection), so a long build never occupies a connection that
# web requests need. Without these, concurrent long builds starved requests
# (the failure that got the earlier attempts reverted).
#
# append: true is the "Add a recipe" path on the edit page: the extracted
# recipes go on the end of the packet's existing ones (title kept, new
# equipment merged in) instead of replacing them. A failed append leaves the
# packet ready with its recipes intact and the error on extract_error.
class ExtractRecipeJob < ApplicationJob
  queue_as :extraction
  limits_concurrency to: 1, key: "recipe_extract", duration: 20.minutes

  def perform(packet_id, user_id = nil, append: false)
    packet = KitchenPacket.find_by(id: packet_id)
    return unless packet&.building? # deleted or already processed: nothing to do

    user = User.find_by(id: user_id)

    # --- Stage: reading the source ---
    packet.update!(build_stage: "reading")
    pdf  = packet.source_document.attached? ? packet.source_document.download : nil
    text = packet.source_text.presence
    url  = packet.source_url.presence

    # --- Stage: writing the recipe (Opus) ---
    packet.update!(build_stage: "recipes")
    result = with_released_connection do
      KitchenAi::RecipeExtractor.new(user: user).extract(text: text, pdf: pdf, url: url)
    end
    unless result.ok?
      packet.update!(status: append ? "ready" : "failed", extract_error: result.error, build_stage: nil)
      return
    end
    if append
      packet.reload # pick up any edits saved while the AI call was in flight
      packet.recipes = packet.recipes + result.recipes
    else
      packet.title = result.recipes.first["title"] if packet.title == KitchenPacket::BUILDING_TITLE
      packet.recipes = result.recipes
    end
    packet.extract_cost_cents = result.cost_cents
    packet.save!

    # --- Stage: equipment (best effort; a miss never fails the packet) ---
    packet.update!(build_stage: "equipment")
    eq = with_released_connection do
      KitchenAi::RecipeExtractor.new(user: user).suggest_equipment(class_name: packet.title, recipes: packet.recipes)
    end
    if eq.ok? && eq.equipment.present?
      packet.equipment = append ? (packet.equipment + eq.equipment).uniq : eq.equipment
    end

    # --- Done ---
    packet.status        = "ready"
    packet.build_stage   = "ready"
    packet.extract_error = nil
    packet.source_text   = nil
    packet.save!
    packet.source_document.purge_later if packet.source_document.attached?
  end

  private

  # Hand the primary DB connection back to the pool for the duration of the
  # block (a long, DB-free Opus call). Any query inside transparently checks a
  # connection back out, so this only frees it while we are waiting on the API.
  def with_released_connection
    ActiveRecord::Base.connection_pool.release_connection
    yield
  end
end
