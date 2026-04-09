class AddRoleClassToJobs < ActiveRecord::Migration[8.1]
  def up
    add_column :jobs, :role_class, :string, default: "traditional", null: false
    add_index :jobs, :role_class

    # Backfill from existing ai_augmented boolean. The reclassify rake task
    # will then upgrade matching rows to "agent_director".
    execute "UPDATE jobs SET role_class = 'ai_augmented' WHERE ai_augmented = 1"
  end

  def down
    remove_index :jobs, :role_class
    remove_column :jobs, :role_class
  end
end
