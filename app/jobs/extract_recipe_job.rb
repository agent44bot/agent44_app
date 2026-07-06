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
class ExtractRecipeJob < ApplicationJob
  queue_as :extraction
  limits_concurrency to: 1, key: "recipe_extract", duration: 20.minutes

  def perform(packet_id, user_id = nil)
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
      packet.update!(status: "failed", extract_error: result.error, build_stage: nil)
      return
    end
    packet.title = result.recipes.first["title"] if packet.title == KitchenPacket::BUILDING_TITLE
    packet.recipes = result.recipes
    packet.extract_cost_cents = result.cost_cents
    packet.save!

    # --- Stage: equipment (best effort; a miss never fails the packet) ---
    packet.update!(build_stage: "equipment")
    eq = with_released_connection do
      KitchenAi::RecipeExtractor.new(user: user).suggest_equipment(class_name: packet.title, recipes: packet.recipes)
    end
    packet.equipment = eq.equipment if eq.ok? && eq.equipment.present?

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
