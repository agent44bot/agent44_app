# Hand edits to a class's pull sheet (Lora and Caitlin, 2026-09-09). The AI
# aggregation is a cache keyed by recipe content; this is the durable layer
# on top: one row per class (event_url) per workspace holding the edited
# categories/items. base_key remembers which generated list the edits were
# made against so the page can say when the recipes have changed since.
class CreatePullSheetEdits < ActiveRecord::Migration[8.1]
  def change
    create_table :pull_sheet_edits do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :event_url, null: false
      t.string :base_key
      t.json :categories, null: false, default: []
      t.json :to_taste, null: false, default: []
      t.references :updated_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :pull_sheet_edits, [ :workspace_id, :event_url ], unique: true
  end
end
