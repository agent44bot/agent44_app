class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "noreply@agent44labs.com")
  layout "mailer"
end
