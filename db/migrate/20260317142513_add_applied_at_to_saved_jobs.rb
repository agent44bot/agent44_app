class AddAppliedAtToSavedJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :saved_jobs, :applied_at, :datetime
  end
end
