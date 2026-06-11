class CreateKitchenHandouts < ActiveRecord::Migration[8.1]
  def change
    # A printable recipe packet for a class. `data` holds the structured
    # recipes (title, ingredient lines with full + single-station quantities,
    # direction sections); see KitchenHandout for the shape.
    create_table :kitchen_handouts do |t|
      t.string :title, null: false
      t.string :station_label, null: false, default: "Single station"
      t.json :data, null: false, default: {}
      t.timestamps
    end

    # Classes the handout is attached to, keyed by event URL. KitchenEvent
    # rows are snapshot-scoped (recreated daily), so the URL is the stable
    # identity of a class; one handout can serve many runs of the same class.
    create_table :kitchen_handout_links do |t|
      t.references :kitchen_handout, null: false, foreign_key: true
      t.string :event_url, null: false
      t.timestamps
    end
    add_index :kitchen_handout_links, :event_url, unique: true
  end
end
