class AddSourceToLinkScans < ActiveRecord::Migration[8.1]
  def change
    # Where a QR scan came from: "display" (the tasting-room screen, tracked but
    # not billed) vs null/"flyer" (a printed flyer/poster, billed). Lets us keep
    # display scans off NYK's bill while still counting them.
    add_column :link_scans, :source, :string
  end
end
