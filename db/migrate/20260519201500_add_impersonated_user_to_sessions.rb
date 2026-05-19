class AddImpersonatedUserToSessions < ActiveRecord::Migration[8.1]
  def change
    add_reference :sessions, :impersonated_user, foreign_key: { to_table: :users }, null: true
  end
end
