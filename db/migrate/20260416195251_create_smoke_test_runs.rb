class CreateSmokeTestRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :smoke_test_runs do |t|
      t.string :name, null: false
      t.string :status, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :duration_ms
      t.text :summary
      t.text :error_message

      t.timestamps
    end

    add_index :smoke_test_runs, [ :name, :started_at ]
    add_index :smoke_test_runs, :started_at
  end
end
