class ApplicationMailer < ActionMailer::Base
  # We send as rich@agent44labs.com (both domains are Brevo-DKIM authenticated),
  # but agent44labs.com has no MX records, so a reply to it would bounce. Mail
  # that invites a reply, like the customer usage statement, has to come back
  # somewhere real, so Reply-To points at agent44labs.ai, which Mailgun
  # receives. Drop MAILER_REPLY_TO once .com can accept mail of its own.
  default from:     ENV.fetch("MAILER_FROM", "rich@agent44labs.com"),
          reply_to: ENV.fetch("MAILER_REPLY_TO", "rich@agent44labs.ai")
  layout "mailer"
end
