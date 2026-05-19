class AddPricingVisibleToMembersToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    # Site-admin-controlled toggle. When true, workspace members see $
    # amounts (per-agent work cost) on their workspace pages. Default
    # false matches the pre-existing 'admins only see pricing' behavior.
    add_column :workspaces, :pricing_visible_to_members, :boolean, default: false, null: false
  end
end
