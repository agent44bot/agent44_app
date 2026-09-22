# In-app feedback (Rich, 2026-09-22): a Feedback button on every page lets a
# signed-in user send a message plus screenshots/files straight to Rich,
# instead of emailing him. Status moves received -> in_progress -> shipped
# (or closed); shipping emails the sender.
class CreateFeedbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :feedbacks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :workspace, foreign_key: true
      t.text :message, null: false
      t.string :page_url
      t.string :status, null: false, default: "received"
      t.text :reply
      t.datetime :shipped_at
      t.timestamps
    end
    add_index :feedbacks, [ :status, :created_at ]
  end
end
