# "Double" / "Single" instead of "Dual station" / "Single station" on the
# recipe handout (Lora and Caitlin, 2026-09-09). Only rows still on the old
# default are renamed; a custom label someone typed is left alone.
class RenameStationLabelsToSingle < ActiveRecord::Migration[8.1]
  def up
    change_column_default :kitchen_packets, :station_label, from: "Single station", to: "Single"
    execute "UPDATE kitchen_packets SET station_label = 'Single' WHERE station_label = 'Single station'"
  end

  def down
    change_column_default :kitchen_packets, :station_label, from: "Single", to: "Single station"
    execute "UPDATE kitchen_packets SET station_label = 'Single station' WHERE station_label = 'Single'"
  end
end
