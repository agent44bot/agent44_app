class BackfillMemberRoleToUser < ActiveRecord::Migration[8.1]
  def up
    # The 'member' role was a prospective-customer state with its own
    # fleet-dashboard-at-/ rendering. Collapsing into 'user' (the default)
    # ahead of the agents-fleet pivot — there's now one customer shape.
    execute "UPDATE users SET role = 'user' WHERE role = 'member'"
    change_column_default :users, :role, "user"
  end

  def down
    change_column_default :users, :role, "member"
  end
end
