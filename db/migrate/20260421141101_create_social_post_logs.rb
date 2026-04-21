class CreateSocialPostLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :social_post_logs do |t|
      t.string :event_url
      t.datetime :copied_at
      t.datetime :posted_at

      t.timestamps
    end
    add_index :social_post_logs, :event_url, unique: true
  end
end
