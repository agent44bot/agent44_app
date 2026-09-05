# Multi-tenant slice 1: give every kitchen table a workspace and mark which
# workspaces run the kitchen feature set. Everything existing belongs to NY
# Kitchen, so backfill to that workspace. Columns stay nullable for now (the
# jobs and API still write without a workspace until slice 3); the two unique
# indexes that made a second tenant impossible become per-workspace.
class AddWorkspaceToKitchenTables < ActiveRecord::Migration[8.1]
  TABLES = %i[
    kitchen_snapshots kitchen_manual_classes kitchen_packets kitchen_packet_links
    smoke_test_runs grocery_receipts ingredient_prices inventory_items
  ].freeze

  def up
    add_column :workspaces, :kitchen_enabled, :boolean, default: false, null: false

    TABLES.each do |t|
      add_reference t, :workspace, foreign_key: true, null: true
    end

    remove_index :kitchen_snapshots, :taken_on
    add_index :kitchen_snapshots, [ :workspace_id, :taken_on ], unique: true
    remove_index :kitchen_packet_links, :event_url
    add_index :kitchen_packet_links, [ :workspace_id, :event_url ], unique: true

    nyk = select_value("SELECT id FROM workspaces WHERE slug = 'nykitchen'")
    return unless nyk

    execute "UPDATE workspaces SET kitchen_enabled = 1 WHERE id = #{nyk.to_i}"
    TABLES.each do |t|
      execute "UPDATE #{t} SET workspace_id = #{nyk.to_i} WHERE workspace_id IS NULL"
    end
  end

  def down
    remove_index :kitchen_packet_links, [ :workspace_id, :event_url ]
    add_index :kitchen_packet_links, :event_url, unique: true
    remove_index :kitchen_snapshots, [ :workspace_id, :taken_on ]
    add_index :kitchen_snapshots, :taken_on, unique: true
    TABLES.each { |t| remove_reference t, :workspace, foreign_key: true }
    remove_column :workspaces, :kitchen_enabled
  end
end
