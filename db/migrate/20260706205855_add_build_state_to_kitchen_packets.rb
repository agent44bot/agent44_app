class AddBuildStateToKitchenPackets < ActiveRecord::Migration[8.1]
  def change
    # Extraction runs in the background with a navbar progress bar, so a packet
    # exists "building" (walking build_stage: reading -> recipes -> equipment ->
    # ready) before its recipes land. Existing rows are already done: default
    # "ready". source_text holds the pasted source until the job consumes it.
    add_column :kitchen_packets, :status, :string, null: false, default: "ready"
    add_column :kitchen_packets, :build_stage, :string
    add_column :kitchen_packets, :extract_error, :text
    add_column :kitchen_packets, :source_text, :text
  end
end
