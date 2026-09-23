# Diff stats for the agent's PR (files changed, lines added and removed),
# shown on the Pull request card. Optional: older PRs never reported them.
class AddPrDiffStatsToFeedbacks < ActiveRecord::Migration[8.1]
  def change
    add_column :feedbacks, :pr_files_changed, :integer
    add_column :feedbacks, :pr_additions, :integer
    add_column :feedbacks, :pr_deletions, :integer
  end
end
