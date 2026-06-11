class WellKnownController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :enforce_workspace_scope, raise: false

  # Apple App Site Association. Enables:
  #   • applinks      — the passwordless magic link (/sign_in/link) AND in-app
  #     deep links (the report's "Open the ..." buttons, e.g. /nykitchen/test)
  #     open the app instead of Safari; the web appUrlOpen handler then routes
  #     the webview to the path.
  #   • webcredentials — passkeys / Face ID work inside the WKWebView
  # Must be served at the apex over https as application/json with no redirect.
  # appID = <team>.<bundle> = MKN95GAN66.com.agent44labs.app.
  # Note: AASA changes propagate via Apple's CDN cache, so an already-installed
  # app may take up to ~24h (or an app reinstall) to honor newly added paths.
  APP_ID = "MKN95GAN66.com.agent44labs.app".freeze

  # Paths that open the native app when tapped on a device that has it
  # installed. "/nykitchen/*" covers every agent page the report links to
  # (analyst, test, data, list, ...).
  APP_LINK_PATHS = [ "/sign_in/*", "/get", "/nykitchen/*" ].freeze

  def apple_app_site_association
    render json: {
      applinks: {
        details: [
          # Legacy format (older iOS) + modern components — belt-and-suspenders
          # so both the magic link and the in-app deep links reliably open the app.
          { "appID" => APP_ID, "paths" => APP_LINK_PATHS },
          {
            "appIDs" => [ APP_ID ],
            "components" => [
              { "/" => "/sign_in/*", "comment" => "passwordless magic link opens the app" },
              { "/" => "/get", "comment" => "QR smart-link opens the app if installed (needs app build claiming /get)" },
              { "/" => "/nykitchen/*", "comment" => "in-app deep links (report buttons) open the app" }
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
