class AddLinkCardToWorkspaceDrafts < ActiveRecord::Migration[8.1]
  def change
    # When true, publish this draft as a link preview card (clickable image
    # that opens source_url) instead of a native image attachment. Used for
    # class promos so the photo itself links to the signup page.
    add_column :workspace_drafts, :link_card, :boolean, default: false, null: false
  end
end
