class CreateUsageEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :usage_events do |t|
      t.references :workspace, null: false, foreign_key: true
      # Who clicked. Nullable + nullify on user delete so a usage record
      # survives an account deletion (Apple-required delete-account flow). No
      # DB FK; the User has_many handles nullify at the app layer.
      t.integer :user_id

      t.string  :kind, null: false           # e.g. "report.on_demand", "report.email"
      t.integer :quantity,   null: false, default: 1
      t.integer :unit_cents, null: false, default: 0 # metered price per unit; we log now, bill later
      t.text    :metadata                    # JSON: per-event context (recipient, snapshot date, ...)

      t.timestamps
    end

    add_index :usage_events, %i[workspace_id created_at]
    add_index :usage_events, :user_id
    add_index :usage_events, :kind
  end
end
