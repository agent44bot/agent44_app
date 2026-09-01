require "test_helper"

class MailerAddressesTest < ActionMailer::TestCase
  # agent44labs.com sends but cannot receive (no MX), so every outgoing mail
  # has to carry a Reply-To on a domain that can. The statement copy tells the
  # customer to reply, and a bounced reply from Lora is a silent failure.
  test "mail comes from .com and replies route to a domain with a mailbox" do
    invoice = build_invoice
    mail = InvoiceMailer.monthly_statement(invoice, to: "someone@example.com")

    assert_equal [ "rich@agent44labs.com" ], mail.from
    assert_equal [ "rich@agent44labs.ai" ],  mail.reply_to
  end

  test "the invoice we send ourselves carries the same headers" do
    mail = InvoiceMailer.monthly_invoice(build_invoice)

    assert_equal [ "rich@agent44labs.com" ], mail.from
    assert_equal [ "rich@agent44labs.ai" ],  mail.reply_to
  end

  private

  def build_invoice
    owner = User.create!(email_address: "owner-#{SecureRandom.hex(4)}@example.com")
    ws = Workspace.create!(name: "NY Kitchen", slug: "nykitchen", owner: owner,
                           timezone: "UTC", base_fee_waived: true, discount_percent: 95)
    Invoice.generate_for(ws, Date.new(2026, 5, 15))
  end
end
