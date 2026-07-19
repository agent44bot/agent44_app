class CreateAgentMemories < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_memories do |t|
      t.references :agent, null: false, foreign_key: true
      t.string :title
      t.text :body, null: false
      t.string :filename
      t.datetime :occurred_at
      t.string :source

      t.timestamps
    end

    add_index :agent_memories, [ :agent_id, :occurred_at ]
    add_index :agent_memories, [ :agent_id, :filename ], unique: true
  end
end
