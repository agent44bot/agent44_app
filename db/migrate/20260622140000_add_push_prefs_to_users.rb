class AddPushPrefsToUsers < ActiveRecord::Migration[8.1]
  def change
    # Per-platform push opt-out, checked by ApnsPusher (iOS) and FcmPusher
    # (Android) before sending. Default on so existing devices keep working;
    # lets us enable Android for a single test user without code changes.
    add_column :users, :ios_push_enabled, :boolean, default: true, null: false
    add_column :users, :android_push_enabled, :boolean, default: true, null: false
  end
end
