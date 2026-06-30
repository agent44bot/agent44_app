class CreateConnectChatMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :connect_chat_messages do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true # nullified if the asker deletes their account
      t.string :platform, null: false
      t.string :role, null: false # "user" (the question) or "assistant" (the reply)
      t.text :content, null: false
      t.timestamps
    end
    add_index :connect_chat_messages, [ :workspace_id, :created_at ]
  end
end
