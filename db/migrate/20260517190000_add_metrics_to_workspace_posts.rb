class AddMetricsToWorkspacePosts < ActiveRecord::Migration[8.1]
  def change
    add_column :workspace_posts, :impressions,       :integer, default: 0, null: false
    add_column :workspace_posts, :likes,             :integer, default: 0, null: false
    add_column :workspace_posts, :reposts,           :integer, default: 0, null: false
    add_column :workspace_posts, :replies,           :integer, default: 0, null: false
    add_column :workspace_posts, :quotes,            :integer, default: 0, null: false
    add_column :workspace_posts, :bookmarks,         :integer, default: 0, null: false
    add_column :workspace_posts, :metrics_synced_at, :datetime
    add_index  :workspace_posts, :metrics_synced_at
  end
end
