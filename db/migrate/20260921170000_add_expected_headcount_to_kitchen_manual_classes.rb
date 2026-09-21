# Hand-added classes (private bookings, camps, WST events) aren't ticketed, so
# the pull sheet has no tickets_sold to scale amounts from. Caitlin knows the
# number for a private booking, so she enters it on the class.
class AddExpectedHeadcountToKitchenManualClasses < ActiveRecord::Migration[8.1]
  def change
    add_column :kitchen_manual_classes, :expected_headcount, :integer
  end
end
