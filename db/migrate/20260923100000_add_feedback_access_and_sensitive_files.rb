# Feedback hardening (2026-09-23):
# - users.feedback_access: only people Rich switches on (on /admin/users) see
#   the Feedback button and can send feedback. Off for everyone by default,
#   so a new sign-up can't put text in front of the feedback agent.
# - feedbacks.pr_sensitive_files: files in the agent's PR that touch sign-in,
#   permissions or roles, so the board can flag it "read carefully".
class AddFeedbackAccessAndSensitiveFiles < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :feedback_access, :boolean, null: false, default: false
    add_column :feedbacks, :pr_sensitive_files, :json, null: false, default: []
  end
end
