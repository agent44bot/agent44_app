class ApplicationMailer < ActionMailer::Base
  # Prod sets MAILER_FROM to rich@agent44labs.ai (the Brevo-authenticated
  # sending domain, and the one with MX records that can receive a reply).
  # The fallback matches it so mailer previews and dev sends show the address
  # customers actually see, rather than a noreply@ on a domain with no mailbox.
  default from: ENV.fetch("MAILER_FROM", "rich@agent44labs.ai")
  layout "mailer"
end
