class CreateSocialLeads < ActiveRecord::Migration[8.1]
  def change
    create_table :social_leads do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string   :platform,      null: false            # "bluesky" | "reddit"
      t.string   :external_id,   null: false            # post uri/id, for dedup
      t.string   :author                                # handle / username
      t.text     :text,          null: false            # the post content
      t.string   :url                                   # link to the post
      t.datetime :posted_at                             # when the original posted
      t.integer  :score,         null: false, default: 0 # AI relevance 0-100
      t.string   :reason                                # why relevant / the angle
      t.text     :draft_reply                           # AI-drafted reply
      t.string   :matched_query                         # keyword that surfaced it
      t.string   :status,        null: false, default: "new" # new | sent | dismissed
      t.timestamps
    end

    add_index :social_leads, %i[workspace_id platform external_id], unique: true,
              name: "index_social_leads_on_ws_platform_external"
    add_index :social_leads, %i[workspace_id status]
  end
end
