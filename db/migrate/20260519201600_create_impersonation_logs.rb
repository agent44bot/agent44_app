class CreateImpersonationLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :impersonation_logs do |t|
      t.references :actor,  foreign_key: { to_table: :users }, null: false
      t.references :target, foreign_key: { to_table: :users }, null: false
      t.string :event,      null: false
      t.string :ip_address
      t.datetime :created_at, null: false
    end
    add_index :impersonation_logs, :created_at
  end
end
