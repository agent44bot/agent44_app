# Passkey (WebAuthn) configuration. The RP ID must equal the domain users see;
# in the iOS app that's the WKWebView's origin (https://agent44labs.com), which
# is also where the web app lives. Locally it's localhost so passkeys can be
# exercised in dev/test.
WebAuthn.configure do |config|
  if Rails.env.production?
    config.allowed_origins = ["https://agent44labs.com"]
    config.rp_id           = "agent44labs.com"
  else
    config.allowed_origins = ["http://localhost:3000", "https://agent44labs.com"]
    config.rp_id           = "localhost"
  end

  config.rp_name = "Agent44 Labs"
  config.credential_options_timeout = 120_000 # ms
end
