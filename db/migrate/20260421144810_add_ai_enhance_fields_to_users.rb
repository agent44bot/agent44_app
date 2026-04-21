class AddAiEnhanceFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :ai_enhances_used, :integer, default: 0, null: false
    add_column :users, :anthropic_api_key, :string
  end
end
