class CreateKitchenEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :kitchen_events do |t|
      t.references :kitchen_snapshot, null: false, foreign_key: true
      t.string :url, null: false
      t.string :name
      t.datetime :start_at
      t.datetime :end_at
      t.string :price
      t.string :availability
      t.string :venue
      t.string :instructor
      t.text :description
      t.integer :spots_left
      t.integer :capacity
      t.timestamps
    end

    add_index :kitchen_events, [ :kitchen_snapshot_id, :url ], unique: true
  end
end
