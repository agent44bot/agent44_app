# Runs recipe extraction (Opus, tens of seconds) off the web request so an
# upload returns instantly and the editor page fills in when the recipes land.
# Reads the packet's source (attached PDF, source_url, or pasted source_text),
# extracts, and moves the packet to "ready" (or "failed" with the error).
class ExtractRecipeJob < ApplicationJob
  queue_as :default

  def perform(packet_id, user_id = nil)
    packet = KitchenPacket.find_by(id: packet_id)
    return unless packet&.building? # deleted or already processed: nothing to do

    user = User.find_by(id: user_id)
    pdf  = packet.source_document.attached? ? packet.source_document.download : nil

    result = KitchenAi::RecipeExtractor.new(user: user).extract(
      text: packet.source_text.presence,
      pdf:  pdf,
      url:  packet.source_url.presence
    )

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
