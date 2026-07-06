class AddBuildStateToKitchenPackets < ActiveRecord::Migration[8.1]
  def change
    # Recipe extraction now runs in a background job, so a packet exists in a
    # "building" state before its recipes land. Existing rows are already
    # extracted, so default them to "ready".
    add_column :kitchen_packets, :status, :string, null: false, default: "ready"
    add_column :kitchen_packets, :extract_error, :text
    # The pasted-text source, kept until the job consumes it (PDF is an
    # ActiveStorage attachment; a URL lives in source_url).
    add_column :kitchen_packets, :source_text, :text
  end
end
