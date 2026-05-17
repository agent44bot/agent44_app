class AddImageUrlToWorkspaceDraftsAndPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :workspace_drafts, :image_url, :string
    add_column :workspace_posts,  :image_url, :string
  end
end
