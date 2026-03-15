class CreatePageViews < ActiveRecord::Migration[8.1]
  def change
    create_table :page_views do |t|
      t.string :path, null: false
      t.string :ip_address
      t.text :user_agent
      t.string :browser
      t.string :device_type
      t.string :os
      t.text :referrer
      t.string :country
      t.string :city
      t.float :latitude
      t.float :longitude
      t.string :session_id
      t.references :user, null: true, foreign_key: true

      t.timestamps
    end

    add_index :page_views, :path
    add_index :page_views, :session_id
    add_index :page_views, :created_at
    add_index :page_views, :country
    add_index :page_views, [:created_at, :path]
  end
end
