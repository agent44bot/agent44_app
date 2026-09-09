# A class's pull sheet after someone edited it by hand: the categories and
# items exactly as they should print, replacing the AI-aggregated list for
# that class. Kept per workspace + event_url. base_key is the cache key of
# the generated list the edits started from; when it no longer matches the
# current recipes, the sheet shows a "recipes changed" note but keeps the
# edits (a hand edit is never silently thrown away).
class PullSheetEdit < ApplicationRecord
  belongs_to :workspace
  belongs_to :updated_by, class_name: "User", optional: true

  validates :event_url, presence: true, uniqueness: { scope: :workspace_id }
  validate :categories_well_formed

  MAX_CATEGORIES = 30
  MAX_ITEMS = 300

  # Normalize a submitted list: strings trimmed, blank items dropped, empty
  # categories kept only if named (so a fresh section survives until filled).
  # Prices are never kept: a pull sheet is for the cook line and hides cost.
  def self.clean_categories(raw)
    Array(raw).first(MAX_CATEGORIES).filter_map do |cat|
      next unless cat.respond_to?(:to_h) && !cat.is_a?(String)
      cat = cat.to_h.stringify_keys
      name = cat["name"].to_s.strip
      items = Array(cat["items"]).first(MAX_ITEMS).filter_map do |it|
        next unless it.respond_to?(:to_h) && !it.is_a?(String)
        it = it.to_h.stringify_keys
        qty = it["quantity"].to_s.strip
        item = it["item"].to_s.strip
        next if item.blank? && qty.blank?
        { "quantity" => qty, "item" => item }
      end
      next if name.blank? && items.empty?
      { "name" => name.presence || "Items", "items" => items }
    end
  end

  # What the pull sheet renders: same shape as the aggregator's Result so the
  # view, PDF, and spreadsheet code need no special case.
  def result
    KitchenAi::GroceryAggregator::Result.new(ok?: true, categories: categories, to_taste: Array(to_taste), cost_cents: nil)
  end

  def stale_against?(key) = base_key.present? && base_key != key

  private

  def categories_well_formed
    unless categories.is_a?(Array) && categories.all? { |c| c.is_a?(Hash) && c["items"].is_a?(Array) }
      errors.add(:categories, "must be a list of sections with items")
    end
  end
end
