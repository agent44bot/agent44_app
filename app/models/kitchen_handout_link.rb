# Joins a KitchenHandout to a class by event URL (the stable class identity;
# KitchenEvent rows are snapshot-scoped and recreated daily). Unique per URL:
# a class carries at most one handout.
class KitchenHandoutLink < ApplicationRecord
  belongs_to :kitchen_handout

  validates :event_url, presence: true, uniqueness: true
end
