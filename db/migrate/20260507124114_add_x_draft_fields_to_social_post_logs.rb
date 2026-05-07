class AddXDraftFieldsToSocialPostLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :social_post_logs, :x_draft_text, :text
    add_column :social_post_logs, :x_drafted_at, :datetime
    add_column :social_post_logs, :x_post_id, :string
    add_column :social_post_logs, :x_posted_at, :datetime
    add_column :social_post_logs, :x_skipped_at, :datetime
    add_column :social_post_logs, :x_approval_token, :string
    add_index :social_post_logs, :x_approval_token
  end
end
