# A printable recipe packet for a NY Kitchen class. Created by pasting or
# uploading the class recipe; KitchenAi::RecipeExtractor turns it into the
# structured `data` below, a member reviews/edits it, and the print view
# renders the full-quantity pages followed by the scaled station pages.
#
# data shape:
#   {
#     "recipes" => [
#       {
#         "title"       => "Fresh Pasta",
#         "ingredients" => [
#           { "qty" => "2½ c", "station_qty" => "1¼ c", "item" => "All-purpose flour", "section" => nil },
#           { "qty" => "",     "station_qty" => "",     "item" => "Salt, to taste",    "section" => nil }
#         ],
#         "directions" => [
#           { "section" => nil, "steps" => [ "Pour flour in a medium mixing bowl...", ... ] }
#         ]
#       }
#     ]
#   }
#
# Quantities are stored as display text for BOTH versions (no fraction math
# in Ruby): the extractor proposes the station quantities and a human fixes
# them in review, so ranges ("2-3 cloves") and "to taste" lines just work.
class KitchenHandout < ApplicationRecord
  has_many :links, class_name: "KitchenHandoutLink", dependent: :destroy

  validates :title, presence: true
  validate :recipes_must_be_well_formed

  def recipes
    Array(data["recipes"])
  end

  # What the Opus extraction cost, as a short dollar string ("$0.04"), or nil
  # when unknown (older handouts / reused packets that skipped extraction).
  def extract_cost_label
    return if extract_cost_cents.blank?
    " (cost #{format('$%.2f', extract_cost_cents / 100.0)})"
  end

  def recipes=(list)
    self.data = data.merge("recipes" => list)
  end

  # The handout attached to a class, by its stable identity (event URL).
  def self.for_event_url(url)
    joins(:links).find_by(kitchen_handout_links: { event_url: url })
  end

  # Attach to a class; a class can only carry one handout, so an existing
  # link for that URL moves to this handout (re-linking a reused packet).
  def attach_to!(event_url)
    KitchenHandoutLink.where(event_url: event_url).destroy_all
    links.create!(event_url: event_url)
  end

  private

  def recipes_must_be_well_formed
    return errors.add(:data, "must include a recipes list") if recipes.empty?
    recipes.each do |r|
      errors.add(:data, "every recipe needs a title") if r["title"].blank?
    end
  end
end
