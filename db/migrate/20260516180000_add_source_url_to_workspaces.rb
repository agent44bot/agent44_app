class AddSourceUrlToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :source_url, :string
  end
end
