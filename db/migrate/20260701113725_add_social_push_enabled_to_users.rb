class AddSocialPushEnabledToUsers < ActiveRecord::Migration[8.1]
  def change
    # Opt-out: on by default, users turn it off in Settings. Gates the Echo
    # social engagement push (new likes/reposts/replies on X + Bluesky).
    add_column :users, :social_push_enabled, :boolean, default: true, null: false
  end
end
