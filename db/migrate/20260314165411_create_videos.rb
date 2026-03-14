class CreateVideos < ActiveRecord::Migration[8.1]
  def change
    create_table :videos do |t|
      t.string :title
      t.string :youtube_id
      t.text :description
      t.integer :position
      t.boolean :published

      t.timestamps
    end
  end
end
