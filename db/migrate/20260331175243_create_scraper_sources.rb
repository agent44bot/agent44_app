class CreateScraperSources < ActiveRecord::Migration[8.1]
  def change
    create_table :scraper_sources do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.boolean :enabled, default: true, null: false
      t.string :source_url
      t.json :search_terms, default: []
      t.string :api_key_name
      t.string :schedule, default: "every_6h", null: false
      t.datetime :last_run_at
      t.string :last_run_status
      t.integer :last_run_jobs_found, default: 0
      t.text :last_run_error
      t.json :config, default: {}

      t.timestamps
    end

    add_index :scraper_sources, :slug, unique: true
    add_index :scraper_sources, :enabled
  end
end
