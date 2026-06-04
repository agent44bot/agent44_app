class WellKnownController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :enforce_workspace_scope, raise: false

  # Apple App Site Association. Enables:
  #   • applinks      — the passwordless magic link (/sign_in/link) opens the app
  #   • webcredentials — passkeys / Face ID work inside the WKWebView
  # Must be served at the apex over https as application/json with no redirect.
  # appID = <team>.<bundle> = MKN95GAN66.com.agent44labs.app.
  APP_ID = "MKN95GAN66.com.agent44labs.app".freeze

  def apple_app_site_association
    render json: {
      applinks: {
        details: [
          # Legacy format (older iOS) + modern components — belt-and-suspenders
          # so the magic link (/sign_in/link) reliably opens the app.
          { "appID" => APP_ID, "paths" => [ "/sign_in/*", "/get" ] },
          {
            "appIDs" => [ APP_ID ],
            "components" => [
              { "/" => "/sign_in/*", "comment" => "passwordless magic link opens the app" },
              { "/" => "/get", "comment" => "QR smart-link opens the app if installed (needs app build claiming /get)" }
            ]
          }
        ]
      },
      webcredentials: {
        apps: [ APP_ID ]
      }
    }
  end
end
