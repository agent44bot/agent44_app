class RenameKitchenHandoutsToPackets < ActiveRecord::Migration[8.1]
  def change
    rename_table  :kitchen_handouts,       :kitchen_packets
    rename_table  :kitchen_handout_links,  :kitchen_packet_links
    rename_column :kitchen_packet_links, :kitchen_handout_id, :kitchen_packet_id
  end
end
