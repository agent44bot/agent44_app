# Joins a KitchenPacket to a class by event URL (the stable class identity;
# KitchenEvent rows are snapshot-scoped and recreated daily). Unique per URL:
# a class carries at most one packet.
class KitchenPacketLink < ApplicationRecord
  belongs_to :kitchen_packet
  include KitchenScoped

  validates :event_url, presence: true, uniqueness: { scope: :workspace_id }
end
