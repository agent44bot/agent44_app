class CreateNewsDigests < ActiveRecord::Migration[8.1]
  def change
    create_table :news_digests do |t|
      t.date :date, null: false
      t.text :summary, null: false

      t.timestamps
    end

    add_index :news_digests, :date, unique: true
  end
end
