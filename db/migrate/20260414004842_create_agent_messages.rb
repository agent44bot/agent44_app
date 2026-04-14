class CreateAgentMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_messages do |t|
      t.string :role, null: false, default: "user"
      t.string :agent, null: false, default: "ripley"
      t.text :content, null: false
      t.string :status, null: false, default: "pending"

      t.timestamps
    end

    add_index :agent_messages, :status
    add_index :agent_messages, :created_at
  end
end
