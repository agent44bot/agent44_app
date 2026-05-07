class CreateKvSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :kv_settings do |t|
      t.string :key, null: false
      t.text :value
      t.timestamps
    end
    add_index :kv_settings, :key, unique: true
  end
end
