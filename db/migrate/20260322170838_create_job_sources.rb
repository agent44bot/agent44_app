class CreateJobSources < ActiveRecord::Migration[8.1]
  def change
    create_table :job_sources do |t|
      t.references :job, null: false, foreign_key: true
      t.string :source, null: false
      t.string :url, null: false
      t.string :external_id
      t.timestamps
    end

    add_index :job_sources, [:source, :url], unique: true
    add_index :job_sources, [:job_id, :source], unique: true
  end
end
