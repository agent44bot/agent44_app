class AddFlyerUnitCentsToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    # Per-workspace price (in cents) charged per flyer print-page open and per QR
    # scan. Null → app default (UsageEvent::FLYER_UNIT_CENTS, 44). Set by the
    # workspace owner from the Neon card's cost info dialog. Read at record time,
    # so past UsageEvents keep the rate they were logged at.
    add_column :workspaces, :flyer_unit_cents, :integer
  end
end
