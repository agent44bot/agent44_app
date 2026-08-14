class AddEchoEmailEnabledToWorkspaceMemberships < ActiveRecord::Migration[8.1]
  # Echo's daily 3pm email of new conversations. Opt-out, like the daily class
  # digest: every current and future member is signed up until they turn it off
  # in Settings (or from the unsubscribe link in the email itself).
  def change
    add_column :workspace_memberships, :echo_email_enabled, :boolean, default: true, null: false
  end
end
