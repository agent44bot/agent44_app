class CreateWorkspacePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :workspace_posts do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :author,    null: false, foreign_key: { to_table: :users }
      t.references :social_account, foreign_key: true
      t.string  :platform,  null: false
      t.text    :body,      null: false
      t.string  :status,    null: false, default: "pending"
      t.string  :remote_id
      t.string  :remote_url
      t.text    :error
      t.datetime :posted_at

      t.timestamps
    end

    add_index :workspace_posts, [:workspace_id, :created_at]
    add_index :workspace_posts, :status
  end
end
