class AddSourceUrlToWorkspaceDraftsAndPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :workspace_drafts, :source_url, :string
    add_column :workspace_posts,  :source_url, :string

    add_index :workspace_drafts, [ :workspace_id, :source_url ]
    add_index :workspace_posts,  [ :workspace_id, :source_url ]
  end
end
