class CreateAiCallLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_call_logs do |t|
      t.string  :model,        null: false
      t.string  :source,       null: false
      t.integer :input_tokens,  default: 0, null: false
      t.integer :output_tokens, default: 0, null: false
      t.references :user, null: true, foreign_key: true

      t.timestamps
    end
    add_index :ai_call_logs, :source
    add_index :ai_call_logs, :created_at
  end
end
