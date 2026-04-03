class AddAiAugmentedToJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :jobs, :ai_augmented, :boolean, default: false, null: false
    reversible do |dir|
      dir.up do
        execute "UPDATE jobs SET ai_augmented = 1 WHERE category = 'ai'"
        execute "UPDATE jobs SET category = 'full_time' WHERE category = 'ai'"
      end
    end
  end
end
