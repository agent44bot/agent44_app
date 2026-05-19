class RenameNyKitchenSlug < ActiveRecord::Migration[8.1]
  def up
    # NYK has a special-cased hub at /nykitchen (no hyphen). The workspace
    # slug was 'ny-kitchen', causing the /workspaces card to display a slug
    # that didn't match the final URL. Drop the hyphen so the card text
    # and the URL line up.
    execute "UPDATE workspaces SET slug = 'nykitchen' WHERE slug = 'ny-kitchen'"
  end

  def down
    execute "UPDATE workspaces SET slug = 'ny-kitchen' WHERE slug = 'nykitchen'"
  end
end
