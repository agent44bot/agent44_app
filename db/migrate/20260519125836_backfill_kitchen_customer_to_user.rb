class BackfillKitchenCustomerToUser < ActiveRecord::Migration[8.1]
  def up
    # kitchen_customer was a workspace-shaped role for NYK customers (Lora).
    # With every workspace having its own membership-based identity, the
    # role is redundant. Lora keeps her NY Kitchen workspace membership;
    # pricing/email gates rebase on workspace membership instead of role.
    execute "UPDATE users SET role = 'user' WHERE role = 'kitchen_customer'"
  end

  def down
    # Best-effort restore: mark any user who's a member of the ny-kitchen
    # workspace as kitchen_customer. Not perfect (admins matching the
    # criterion get flipped too) but close enough for rollback.
    execute <<~SQL
      UPDATE users SET role = 'kitchen_customer'
      WHERE id IN (
        SELECT user_id FROM workspace_memberships
        WHERE workspace_id IN (SELECT id FROM workspaces WHERE slug = 'ny-kitchen')
      )
      AND role = 'user'
    SQL
  end
end
