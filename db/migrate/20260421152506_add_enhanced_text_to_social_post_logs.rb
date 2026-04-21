class AddEnhancedTextToSocialPostLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :social_post_logs, :enhanced_text, :text
  end
end
