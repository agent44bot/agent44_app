class CreateApplyRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :apply_requests do |t|
      # One live apply request per job; re-enqueue reuses the row.
      t.references :job, null: false, foreign_key: true, index: { unique: true }
      # queued -> opened -> filled -> applied (or skipped / error). Drives the
      # Mac-Mini Playwright runner (Phase 2), which fills the application up to
      # the submit button and stops for Rich to review.
      t.string   :status, null: false, default: "queued"
      t.datetime :requested_at
      t.datetime :opened_at
      t.datetime :filled_at
      t.datetime :applied_at
      t.text     :notes   # runner progress / error detail
      t.timestamps
    end
    add_index :apply_requests, :status
  end
end
