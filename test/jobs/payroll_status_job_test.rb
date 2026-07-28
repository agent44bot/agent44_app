require "test_helper"
require "minitest/mock"

class PayrollStatusJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @rich = User.create!(email_address: "botwhisperer@hey.com", role: "admin")
    @lora = User.create!(email_address: "lora.downie@nykitchen.com", role: "user")
    Workspace.find_or_create_by!(slug: "nykitchen") { |w| w.name = "NY Kitchen"; w.owner = @rich }
  end

  STATUS = { by_employee: { "Alice" => { approved: 1, pending: 4, total: 5 } },
             total: 5, approved: 1, pending: 4 }.freeze

  test "emails and iOS-pushes exactly Rich + Lora when Deputy is configured" do
    DeputyClient.stub(:configured?, true) do
      DeputyClient.stub(:timesheet_status, STATUS) do
        assert_enqueued_emails 1 do
          # one notify! per recipient user (Rich + Lora) => 2 Notification rows
          assert_difference -> { Notification.count }, 2 do
            PayrollStatusJob.perform_now
          end
        end
      end
    end
    note = Notification.order(:created_at).last
    assert_equal "payroll_status", note.source
    assert_match(/pending/i, note.body)
  end

  test "does nothing when Deputy is not connected" do
    DeputyClient.stub(:configured?, false) do
      assert_no_enqueued_emails do
        assert_no_difference -> { Notification.count } do
          PayrollStatusJob.perform_now
        end
      end
    end
  end

  test "the payroll_status email renders with the Deputy review button and week" do
    mail = KitchenMailer.payroll_status(
      recipients: [ "a@b.com" ], week_start: Date.new(2026, 7, 20), week_end: Date.new(2026, 7, 26),
      status: STATUS, deputy_url: "https://x.na.deputy.com/#/approve-v2", deadline: "Wednesday at 4pm"
    )
    body = mail.body.to_s
    assert_match "Payroll status", body
    assert_match "Review timesheets in Deputy", body
    assert_match "https://x.na.deputy.com/#/approve-v2", body, "Deputy button links to the approve screen"
    assert_match "Jul 20", body
    assert_match "Wednesday at 4pm", body
    assert_match(/Payroll: 4 still pending/, mail.subject)
  end

  test "the email reads all-approved when nothing is pending" do
    approved = { by_employee: { "Alice" => { approved: 5, pending: 0, total: 5 } }, total: 5, approved: 5, pending: 0 }
    mail = KitchenMailer.payroll_status(
      recipients: [ "a@b.com" ], week_start: Date.new(2026, 7, 20), week_end: Date.new(2026, 7, 26),
      status: approved, deputy_url: "https://x.na.deputy.com/#/approve-v2", deadline: "today at 4pm"
    )
    assert_match "ready to run payroll", mail.body.to_s
    assert_match(/all 5 approved/i, mail.subject)
  end
end
