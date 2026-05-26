class CreateLoginCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :login_codes do |t|
      t.string   :email_address, null: false
      t.string   :code_digest,   null: false
      t.datetime :expires_at,    null: false
      t.datetime :consumed_at
      t.integer  :attempt_count, null: false, default: 0
      t.string   :ip_address

      t.timestamps
    end

    add_index :login_codes, :email_address
    add_index :login_codes, :expires_at
  end
end
