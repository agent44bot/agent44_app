class CreateJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :jobs do |t|
      t.string :title, null: false
      t.string :company
      t.string :location
      t.string :url, null: false
      t.string :salary
      t.string :source
      t.text :description
      t.string :category, null: false
      t.string :external_id
      t.datetime :posted_at
      t.boolean :active, default: true

      t.timestamps
    end
    add_index :jobs, [ :source, :url ], unique: true
    add_index :jobs, :category
    add_index :jobs, :posted_at
  end
end
