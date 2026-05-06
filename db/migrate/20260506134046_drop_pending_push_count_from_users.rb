class DropPendingPushCountFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :pending_push_count, :integer, default: 0, null: false
  end
end
