class AddNormalizedFieldsToJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :jobs, :normalized_title, :string
    add_column :jobs, :normalized_company, :string
    add_index :jobs, [:normalized_company, :normalized_title]
  end
end
