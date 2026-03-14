class CreateKeypairAuthChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :keypair_auth_challenges do |t|
      t.string :challenge
      t.string :pubkey_hex
      t.datetime :expires_at
      t.boolean :consumed

      t.timestamps
    end
  end
end
