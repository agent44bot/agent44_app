class AddMethodToPageViews < ActiveRecord::Migration[8.1]
  def change
    add_column :page_views, :method, :string
    # Backfill existing rows — historically we only tracked GETs.
    reversible do |dir|
      dir.up do
        execute "UPDATE page_views SET method = 'GET' WHERE method IS NULL"
      end
    end
  end
end
