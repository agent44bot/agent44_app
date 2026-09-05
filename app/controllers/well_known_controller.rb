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
  #
  # EXCEPTION: "/nykitchen/r/*" (the printed-flyer QR scan redirects) must NOT
  # open the app. Those bounce (302) to nykitchen.com to book a class; if iOS
  # opened our app instead, the customer would land in agent44labs and never
  # reach the class page. The "NOT" rule must precede "/nykitchen/*" — the
  # legacy matcher takes the first match. (Modern iOS uses the components list
  # below, which marks the same path exclude: true.)
  # Kitchen pages mount at /<slug>/* for every kitchen-enabled workspace (NY
  # Kitchen first), so the deep-link list is built per slug at request time.
  BASE_LINK_PATHS = [ "/sign_in/*", "/get" ].freeze

  def self.app_link_paths
    BASE_LINK_PATHS + KitchenWorkspaceConstraint.slugs.flat_map { |s| [ "NOT /#{s}/r/*", "/#{s}/*" ] }
  end

  def app_link_paths = self.class.app_link_paths

  def apple_app_site_association
    render json: {
      applinks: {
        details: [
          # Legacy format (older iOS) + modern components — belt-and-suspenders
          # so both the magic link and the in-app deep links reliably open the app.
          { "appID" => APP_ID, "paths" => app_link_paths },
          {
            "appIDs" => [ APP_ID ],
            "components" => [
              { "/" => "/sign_in/*", "comment" => "passwordless magic link opens the app" },
              { "/" => "/get", "comment" => "QR smart-link opens the app if installed (needs app build claiming /get)" }
            ] + KitchenWorkspaceConstraint.slugs.flat_map { |s|
              [
                { "/" => "/#{s}/r/*", "exclude" => true, "comment" => "flyer QR scan redirects must open in the browser so they follow the 302 to the venue site, not the app" },
                { "/" => "/#{s}/*", "comment" => "in-app deep links (report buttons) open the app" }
              ]
            }
          }
        ]
      },
      webcredentials: {
        apps: [ APP_ID ]
      }
    }
  end
end
