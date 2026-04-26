class CreateKitchenTicketDigests < ActiveRecord::Migration[8.1]
  def change
    create_table :kitchen_ticket_digests do |t|
      t.references :kitchen_snapshot, null: false, foreign_key: true
      t.integer :total_tickets, null: false, default: 0
      t.integer :sold_out_count, null: false, default: 0
      t.integer :change_count, null: false, default: 0
      t.json :entries, null: false, default: []
      t.timestamps
    end

    add_index :kitchen_ticket_digests, :created_at
  end
end
