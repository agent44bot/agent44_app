class CreateNewsArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :news_articles do |t|
      t.string :title, null: false
      t.string :url, null: false
      t.string :source, null: false
      t.text :summary
      t.datetime :published_at
      t.datetime :used_at

      t.timestamps
    end

    add_index :news_articles, :url, unique: true
    add_index :news_articles, :used_at
    add_index :news_articles, :source
  end
end
