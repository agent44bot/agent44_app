class AddBuildStateToKitchenPackets < ActiveRecord::Migration[8.1]
  def change
    # Extraction runs in the background with a navbar progress bar, so a packet
    # exists "building" (walking build_stage: reading -> recipes -> equipment ->
    # ready) before its recipes land. Existing rows are already done: default
    # "ready". source_text holds the pasted source until the job consumes it.
    #
    # if_not_exists: an earlier (reverted) attempt already added status /
    # extract_error / source_text to the prod DB and left them there, so adding
    # them again would crash on boot. Only build_stage is genuinely new in prod;
    # a fresh DB gets all four.
    add_column :kitchen_packets, :status, :string, null: false, default: "ready", if_not_exists: true
    add_column :kitchen_packets, :build_stage, :string, if_not_exists: true
    add_column :kitchen_packets, :extract_error, :text, if_not_exists: true
    add_column :kitchen_packets, :source_text, :text, if_not_exists: true
  end
end
