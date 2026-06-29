class AddBillingFieldsToWorkspaces < ActiveRecord::Migration[8.1]
  def up
    # Per-workspace usage markup (raw Anthropic cost x multiplier). Default 1.0
    # = no markup, so a new workspace's billing page shows true cost until an
    # admin sets a markup. NY Kitchen keeps its existing ENV-based multiplier.
    add_column :workspaces, :usage_multiplier, :decimal, precision: 6, scale: 2, default: 1.0, null: false
    # Opt-in: only billing_enabled workspaces get a monthly invoice generated.
    add_column :workspaces, :billing_enabled, :boolean, default: false, null: false

    # Turn billing on for the workspaces we actually bill today (no-op where the
    # workspace is absent, e.g. test/CI).
    Workspace.reset_column_information
    Workspace.where(slug: %w[nykitchen gems-of-eden]).update_all(billing_enabled: true)
  end

  def down
    remove_column :workspaces, :usage_multiplier
    remove_column :workspaces, :billing_enabled
  end
end
