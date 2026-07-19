class AddCrewProfilesToAgents < ActiveRecord::Migration[8.1]
  # Local model so the backfill doesn't depend on app validations/callbacks.
  class MigrationAgent < ActiveRecord::Base
    self.table_name = "agents"
  end

  def up
    add_column :agents, :slug, :string
    add_column :agents, :soul_markdown, :text
    add_column :agents, :identity_markdown, :text
    add_column :agents, :skills, :json, null: false, default: []

    MigrationAgent.reset_column_information
    MigrationAgent.find_each do |a|
      slug = a.name.to_s.split(/\s+/).first.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      a.update_columns(slug: slug) if slug.present?
    end

    change_column_null :agents, :slug, false
    add_index :agents, :slug, unique: true
  end

  def down
    remove_index :agents, :slug
    remove_column :agents, :slug
    remove_column :agents, :soul_markdown
    remove_column :agents, :identity_markdown
    remove_column :agents, :skills
  end
end
