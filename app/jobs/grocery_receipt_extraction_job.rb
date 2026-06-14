# Reads an uploaded grocery receipt with Opus vision and turns its lines into
# IngredientPrice rows. Runs async because the vision call is slow and paid.
class GroceryReceiptExtractionJob < ApplicationJob
  queue_as :default

  def perform(receipt_id)
    receipt = GroceryReceipt.find_by(id: receipt_id)
    return unless receipt&.image&.attached?

    known  = IngredientPrice.distinct.pluck(:canonical_name)
    result = KitchenAi::ReceiptExtractor.new(user: receipt.created_by).extract(
      image_bytes: receipt.image.download,
      media_type:  receipt.image.content_type,
      known_names: known
    )

    unless result.ok?
      receipt.update!(status: "failed", parse_error: result.error)
      return
    end

    observed_on = receipt.purchased_on || Date.current
    GroceryReceipt.transaction do
      receipt.update!(status: "parsed", store: result.store, total_cents: result.total_cents)
      Array(result.items).each do |it|
        receipt.ingredient_prices.create!(
          canonical_name:   it[:canonical_name],
          unit:             it[:unit],
          unit_price_cents: it[:unit_price_cents],
          quantity:         it[:quantity],
          raw_label:        it[:raw_label],
          observed_on:      observed_on
        )
      end
    end
  end
end
