class AddUserToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_reference :notifications, :user, null: true, foreign_key: true
  end
end
