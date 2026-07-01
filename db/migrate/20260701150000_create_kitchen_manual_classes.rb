class CreateKitchenManualClasses < ActiveRecord::Migration[8.1]
  def change
    create_table :kitchen_manual_classes do |t|
      t.string :name, null: false
      t.datetime :start_at, null: false
      t.datetime :end_at
      t.string :price               # freeform, e.g. "$45"; blank ok
      t.text :notes                 # e.g. "Ages 8-12"
      t.string :venue
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :kitchen_manual_classes, :start_at
  end
end
