class AddEmailVerificationToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_verified_at, :datetime
    add_column :users, :email_verification_token, :string
    add_index :users, :email_verification_token, unique: true
  end
end
