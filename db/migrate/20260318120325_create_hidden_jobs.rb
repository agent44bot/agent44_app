class CreateHiddenJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :hidden_jobs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :job, null: false, foreign_key: true

      t.timestamps
    end
    add_index :hidden_jobs, [:user_id, :job_id], unique: true
  end
end
