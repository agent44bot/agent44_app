class AddPendingPushCountToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :pending_push_count, :integer, default: 0, null: false
  end
end
