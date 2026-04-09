class CreateNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :notifications do |t|
      t.string :level, null: false, default: "info"
      t.string :source, null: false
      t.string :title, null: false
      t.text :body
      t.datetime :read_at

      t.timestamps
    end

    add_index :notifications, :read_at
    add_index :notifications, :created_at
    add_index :notifications, :level
  end
end
