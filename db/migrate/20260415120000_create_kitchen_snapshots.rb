class CreateKitchenSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :kitchen_snapshots do |t|
      t.date :taken_on, null: false
      t.timestamps
    end

    add_index :kitchen_snapshots, :taken_on, unique: true
  end
end
