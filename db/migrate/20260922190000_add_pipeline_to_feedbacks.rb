# Feedback phase 2 (docs/feedback_pipeline.md): the Mac mini plans each item,
# Rich approves (1), the mini builds a PR, Rich taps Merge it (2), the mini
# merges and verifies the deploy. These columns carry that state.
class AddPipelineToFeedbacks < ActiveRecord::Migration[8.1]
  def change
    change_table :feedbacks, bulk: true do |t|
      t.text :plan
      t.json :thread, null: false, default: []
      t.integer :pr_number
      t.string :pr_url
      t.string :pr_head_sha
      t.string :pr_checks
      t.text :pr_summary
      t.text :ship_note
      t.string :merge_requested_sha
      t.text :agent_error
      t.datetime :agent_claimed_at
      t.datetime :planned_at
      t.datetime :approved_at
      t.datetime :pr_ready_at
      t.datetime :merge_requested_at
      t.datetime :closed_at
    end
  end
end
