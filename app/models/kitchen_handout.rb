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

  # Library search: match the packet title and the recipe contents. SQLite
  # stores `data` as JSON text, so a LIKE over it also matches ingredient and
  # direction wording (e.g. searching "ginger" finds packets that use it).
  scope :search, ->(q) {
    if q.present?
      term = "%#{sanitize_sql_like(q.to_s.strip)}%"
      where("title LIKE ? OR data LIKE ?", term, term)
    end
  }

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

  # Equipment to set up at each station before class (pots, pans, wooden
  # spoons...). Lives on the packet so it follows the class to every run; the
  # pull sheet prints it as a per-station setup checklist.
  def equipment
    Array(data["equipment"])
  end

  def equipment=(list)
    self.data = data.merge("equipment" => list)
  end

  # A starter palette of common station equipment so the tag picker isn't empty
  # on day one. Lora/Caitlin grow the real vocabulary just by adding items.
  STARTER_EQUIPMENT = [
    "Cutting board", "Chef's knife", "Paring knife", "Mixing bowls",
    "Measuring cups", "Measuring spoons", "Whisk", "Wooden spoon", "Spatula",
    "Tongs", "Large stockpot", "Saucepan", "Sauté pan", "Sheet pan",
    "Colander", "Strainer", "Ladle", "Peeler", "Box grater", "Kitchen towel"
  ].freeze

  # Setting key holding the equipment tags a manager deleted from the palette
  # for good (JSON array of names).
  HIDDEN_EQUIPMENT_KEY = "equipment_hidden_tags".freeze

  # Tags removed from the palette forever.
  def self.hidden_equipment
    JSON.parse(Setting.get(HIDDEN_EQUIPMENT_KEY).presence || "[]")
  rescue JSON::ParserError
    []
  end

  # Permanently drop a tag from the palette so it stops being suggested.
  def self.hide_equipment(name)
    clean = name.to_s.strip
    return if clean.blank?
    list = hidden_equipment
    return if list.any? { |h| h.casecmp?(clean) }
    Setting.set(HIDDEN_EQUIPMENT_KEY, (list + [ clean ]).to_json)
  end

  # The full set of equipment tags to offer in the picker: the starter palette
  # plus everything ever used on a packet, de-duped (case-insensitive), minus
  # any deleted tags, sorted. Grows organically as new items are added.
  def self.equipment_catalog
    hidden = hidden_equipment.map(&:downcase).to_set
    used = all.flat_map(&:equipment)
    (STARTER_EQUIPMENT + used).map { |e| e.to_s.strip }.reject(&:blank?)
      .uniq { |e| e.downcase }.reject { |e| hidden.include?(e.downcase) }.sort_by(&:downcase)
  end

  # The handout attached to a class, by its stable identity (event URL).
  def self.for_event_url(url)
    joins(:links).find_by(kitchen_handout_links: { event_url: url })
  end

  # Attach to a class; a class can only carry one handout, so an existing
  # link for that URL moves to this handout (re-linking a reused packet).
  # auto: true marks a link the system made by matching the class name (so the
  # UI can badge it); a manual attach (auto: false) clears that mark.
  def attach_to!(event_url, auto: false)
    KitchenHandoutLink.where(event_url: event_url).destroy_all
    links.create!(event_url: event_url, auto: auto)
  end

  # Reuse means COPY, not share: build an independent packet from this one and
  # attach it to the given class. Each class then owns its recipe, so editing
  # or deleting one class's copy never touches the class it was copied from.
  # extract_cost_cents is left blank because copying skips the AI (no cost to
  # attribute); the new link is manual (auto: false), so it stays put.
  def copy_to!(event_url)
    copy = self.class.create!(
      title: title,
      station_label: station_label,
      data: data.deep_dup,
      source_url: source_url,
      source_kind: source_kind
    )
    copy.attach_to!(event_url)
    copy
  end

  private

  def recipes_must_be_well_formed
    return errors.add(:data, "must include a recipes list") if recipes.empty?
    recipes.each do |r|
      errors.add(:data, "every recipe needs a title") if r["title"].blank?
    end
  end
end
