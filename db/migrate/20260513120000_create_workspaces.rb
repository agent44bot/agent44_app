class CreateWorkspaces < ActiveRecord::Migration[8.1]
  def change
    create_table :workspaces do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :slug, null: false
      t.text   :description
      t.string :timezone, null: false, default: "UTC"
      t.text   :settings
      t.datetime :archived_at

      t.timestamps
    end

    add_index :workspaces, :slug, unique: true
    add_index :workspaces, :archived_at
  end
end
