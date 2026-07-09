class CreateTrackedLinksAndScans < ActiveRecord::Migration[8.1]
  def change
    create_table :tracked_links do |t|
      # 12-char SHA of the target url: stable across daily snapshots (which
      # regenerate KitchenEvent rows), so a printed flyer's QR keeps resolving.
      t.string     :token, null: false
      t.string     :url,   null: false
      t.references :workspace, foreign_key: true # nullable: some links are workspace-agnostic
      t.timestamps
    end
    add_index :tracked_links, :token, unique: true

    create_table :link_scans do |t|
      t.references :tracked_link, null: false, foreign_key: true
      t.datetime :scanned_at, null: false
      t.string   :user_agent
      t.string   :referrer
    end
    add_index :link_scans, :scanned_at
  end
end
