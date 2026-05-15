class CreateWorkspaceDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :workspace_drafts do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :author,    null: false, foreign_key: { to_table: :users }
      t.text    :body,             null: false
      t.text    :target_platforms, null: false, default: "[]" # JSON-serialized array
      t.datetime :scheduled_for
      t.string  :status,           null: false, default: "draft"
      t.datetime :published_at
      t.text    :error
      t.text    :results # JSON-serialized per-platform result lines

      t.timestamps
    end

    add_index :workspace_drafts, [:workspace_id, :created_at]
    add_index :workspace_drafts, :status
    add_index :workspace_drafts, :scheduled_for
  end
end
