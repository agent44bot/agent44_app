# Runs recipe extraction (Opus, tens of seconds) off the web request so an
# upload returns instantly and the editor page fills in when the recipes land.
# Reads the packet's source (attached PDF, source_url, or pasted source_text),
# extracts, and moves the packet to "ready" (or "failed" with the error).
#
# Runs on its own queue and one-at-a-time: the extraction is a ~1 minute Opus
# call, and the app runs SolidQueue inside puma sharing a small primary DB
# connection pool with web serving. If several long jobs held connections at
# once they starved requests (that is why the first async attempt was reverted).
# Two guards prevent that: this job hands its DB connection back to the pool
# while it waits on the API, and limits_concurrency keeps only one running.
class ExtractRecipeJob < ApplicationJob
  queue_as :extraction
  limits_concurrency to: 1, key: "recipe_extract", duration: 15.minutes

  def perform(packet_id, user_id = nil)
    packet = KitchenPacket.find_by(id: packet_id)
    return unless packet&.building? # deleted or already processed: nothing to do

    user = User.find_by(id: user_id)
    pdf  = packet.source_document.attached? ? packet.source_document.download : nil
    text = packet.source_text.presence
    url  = packet.source_url.presence

    # The Opus call takes ~a minute and touches no DB. Release the primary
    # connection back to the pool for the duration of the call so a long
    # extraction never occupies a connection web serving needs. Writes below
    # transparently check a connection back out.
    ActiveRecord::Base.connection_pool.release_connection

    result = KitchenAi::RecipeExtractor.new(user: user).extract(text: text, pdf: pdf, url: url)

    if result.ok?
      # If no class name was given up front, title the packet from the recipe.
      packet.title   = result.recipes.first["title"] if packet.title == KitchenPacket::BUILDING_TITLE
      packet.recipes = result.recipes
      packet.status  = "ready"
      packet.extract_cost_cents = result.cost_cents
      packet.extract_error = nil
      packet.source_text   = nil
      packet.save!
      packet.source_document.purge_later if packet.source_document.attached?
    else
      packet.update!(status: "failed", extract_error: result.error)
    end
  end
end
