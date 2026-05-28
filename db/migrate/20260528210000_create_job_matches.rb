class CreateJobMatches < ActiveRecord::Migration[8.0]
  def change
    create_table :job_matches do |t|
      t.references :job, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.integer :score, null: false, default: 0
      t.json :matched_skills
      t.boolean :is_dream, null: false, default: false
      t.json :reasons
      t.datetime :computed_at
      # AI enrichment (JobMatchEnricher) — null until a strong match is enriched.
      t.text :why
      t.text :pitch
      t.json :lead_skills
      t.datetime :enriched_at

      t.timestamps
    end

    add_index :job_matches, :score
  end
end
