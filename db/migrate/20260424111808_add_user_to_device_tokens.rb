class AddUserToDeviceTokens < ActiveRecord::Migration[8.1]
  def change
    add_reference :device_tokens, :user, null: true, foreign_key: true
  end
end
