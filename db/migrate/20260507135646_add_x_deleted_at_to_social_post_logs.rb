class AddXDeletedAtToSocialPostLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :social_post_logs, :x_deleted_at, :datetime
  end
end
