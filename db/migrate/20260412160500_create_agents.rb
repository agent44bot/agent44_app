class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents do |t|
      t.string :name, null: false
      t.string :role, null: false
      t.text :description
      t.string :status, null: false, default: "offline"
      t.string :avatar_color, null: false, default: "orange"
      t.datetime :last_active_at
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :agents, :name, unique: true
    add_index :agents, :position
  end
end
