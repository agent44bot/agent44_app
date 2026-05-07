class CreateFleetRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :fleet_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.text :services, null: false, default: ""
      t.string :status, null: false, default: "pending"
      t.datetime :contacted_at
      t.text :notes

      t.timestamps
    end
    add_index :fleet_requests, :status
    add_index :fleet_requests, :created_at
  end
end
