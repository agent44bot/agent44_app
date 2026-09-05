Rails.application.routes.draw do
  root "pages#home"

  # Apple App Site Association — Universal Links + passkeys (webcredentials).
  get "/.well-known/apple-app-site-association",
      to: "well_known#apple_app_site_association", defaults: { format: "json" }

  get "privacy", to: "pages#privacy"
  # QR-code smart redirect: iOS -> App Store, everyone else -> website.
  # Handled at the routing layer (not a controller action) so it runs before
  # the app-wide `allow_browser` gate — the iOS Camera/QR preview sends a short
  # UA that allow_browser would 406. Routing redirect bypasses that entirely.
  # status 302 (not the redirect{} default 301): the target depends on the
  # User-Agent, so it must never be cached — every scan re-evaluates.
  get "get", as: :get_app, to: redirect(status: 302) { |_params, req|
    ios = req.user_agent.to_s.match?(/iPhone|iPad|iPod/i)
    ios ? "https://apps.apple.com/app/id6762046812" : "https://agent44labs.ai"
  }

  resource :session do
    post :challenge, on: :collection
  end

  # DevSessionsController#create returns 404 outside Rails.env.development?,
  # so the route is safe to expose in prod — it just always 404s there.
  post "dev/login_as/:user_id", to: "dev_sessions#create", as: :dev_login_as

  # Admin "view-as" impersonation. The actor must be a real admin; the
  # target must not be an admin. ImpersonationLog records every start/stop.
  post   "impersonate/:user_id", to: "impersonations#create",  as: :impersonate
  delete "impersonate",          to: "impersonations#destroy", as: :stop_impersonating
  resource :registration, only: [ :new, :create ]
  resources :passwords, param: :token

  # Passwordless sign-in (also sign-up): email → 6-digit code or magic-link
  # button. The primary entry point; password/Nostr login lives under :session.
  get  "sign_in",        to: "sign_ins#new",    as: :sign_in
  post "sign_in",        to: "sign_ins#create"
  get  "sign_in/code",   to: "sign_ins#code",   as: :sign_in_code
  post "sign_in/verify", to: "sign_ins#verify", as: :verify_sign_in
  get  "sign_in/link",   to: "sign_ins#link",   as: :sign_in_link

  # Passkeys (Face ID). Registration is signed-in (Settings); authentication is
  # signed-out (from /sign_in). Discoverable credentials → usernameless.
  post   "settings/passkeys/challenge", to: "passkeys#create_challenge", as: :passkey_create_challenge
  post   "settings/passkeys",           to: "passkeys#create",           as: :passkeys
  delete "settings/passkeys/:id",       to: "passkeys#destroy",          as: :passkey
  post   "sign_in/passkey/challenge",   to: "passkeys#auth_challenge",   as: :passkey_auth_challenge
  post   "sign_in/passkey",             to: "passkeys#authenticate",     as: :passkey_authenticate
  resource :settings, only: [ :show, :destroy ] do
    post  :verify_password
    patch :update_email
    patch :update_name
    patch :update_avatar
    patch :update_notifications
  end
  # Login-free unsubscribe from Echo's daily email (signed token in the URL).
  # GET confirms, POST turns it off, so a prefetching mail scanner can't mute
  # someone by following the link.
  get  "echo_email/unsubscribe/:token", to: "echo_email_subscriptions#show",    as: :echo_email_unsubscribe
  post "echo_email/unsubscribe/:token", to: "echo_email_subscriptions#destroy"

  get "email_verification", to: "email_verifications#show", as: :email_verification
  post "email_verification/resend", to: "email_verifications#resend", as: :resend_email_verification

  resources :jobs, only: [ :index, :show ] do
    collection do
      get :globe
      get :today
      get :for_me
      get :opportunities
      post :run_now
    end
    member do
      post :apply_kit
      post :enqueue_apply
      delete :dismiss
    end
    resource :saved_job, only: [ :create, :destroy ] do
      post :toggle_applied, on: :member
    end
    resource :hidden_job, only: [ :create, :destroy ]
  end
  resources :saved_jobs, only: [ :index ]
  # ---------------------------------------------------------------------------
  # Kitchen feature set, mounted once under a workspace slug. NY Kitchen's
  # slug is "nykitchen", so every URL below is byte-for-byte what it was
  # (/nykitchen/display/print etc. are permanent: QR codes, the display
  # screen, iOS Universal Links); any other kitchen-enabled workspace gets the
  # same pages under /<slug>/... with no code change. The constraint only
  # matches kitchen-enabled slugs (plus nykitchen), so top-level routes such
  # as /jobs or /workspaces can never be shadowed; Workspace also refuses
  # slugs that collide with them. Helper names keep their nyk_ prefix; the
  # :workspace_slug segment is filled from the current request (or NYK by
  # default, see ApplicationController#default_url_options).
  # ---------------------------------------------------------------------------
  scope ":workspace_slug", constraints: KitchenWorkspaceConstraint.new do
    get "",        to: "kitchen#hub", as: :nykitchen
    get "list",   to: "kitchen#list", as: :nyk_list
    get "grocery", to: "kitchen#grocery", as: :nyk_grocery
    # Team hours (scheduled, from Deputy) for managers: per-employee weekly totals
    # + Export to Excel. See KitchenController#hours.
    get "hours", to: "kitchen#hours", as: :nyk_hours
    # Generate pending timesheets in Deputy for a week's shifts (manager-only,
    # idempotent). See KitchenController#generate_timesheets.
    post "hours/timesheets", to: "kitchen#generate_timesheets", as: :nyk_generate_timesheets
    post "grocery/receipts", to: "kitchen#upload_receipt", as: :nyk_grocery_receipts
    patch "grocery/portion", to: "kitchen#update_portion", as: :nyk_grocery_portion
    post "classes",     to: "kitchen#create_manual_class", as: :nyk_manual_classes
    delete "classes/:id", to: "kitchen#destroy_manual_class", as: :nyk_manual_class
    get "prices",     to: "kitchen#prices",       as: :nyk_prices
    patch "prices/:id", to: "kitchen#update_price", as: :nyk_price
    delete "prices/:id", to: "kitchen#destroy_price"
    get "test",   to: "kitchen#test", as: :nyk_test
    get "data",   to: "kitchen#data", as: :nyk_data
    get "analyst", to: "kitchen#analyst", as: :nyk_analyst
    patch "analyst/subscription", to: "kitchen#update_analyst_subscription", as: :nyk_analyst_subscription
    # Admin-only live preview of the weekly Agent Team Report (real data, same
    # builder as the real send). 404s for non-admins. See kitchen#report_preview.
    get "analyst/report", to: "kitchen#report_preview", as: :nyk_report_preview
    # On-demand report for NY Kitchen managers: generate a fresh copy (POST so it
    # isn't re-run on refresh/prefetch); it emails a copy to the logged-in user
    # only. Metered action.
    post "analyst/report/generate", to: "kitchen#generate_report", as: :nyk_generate_report
    get "ask",          to: "kitchen#ask",                as: :nyk_ask
    post "ask/message",  to: "kitchen#ask_message",        as: :nyk_ask_message
    post "ask/examples", to: "kitchen#update_ask_examples", as: :nyk_ask_examples
    # Public, no-auth screen for the tasting-room display monitor.
    # Cycles currently-available classes; auto-refreshes periodically.
    get "display", to: "kitchen#display", as: :nyk_display
    # Liveness ping from the live screen (private mode only). Records last-seen
    # so the hub's Display Agent dot reflects whether the TV is actually on.
    post "display/heartbeat", to: "kitchen#display_heartbeat", as: :nyk_display_heartbeat
    # Display Agent admin: hub-card detail page with config form.
    get "display/settings", to: "kitchen#display_settings",        as: :nyk_display_settings
    patch "display/settings", to: "kitchen#update_display_settings"
    post "display/rotate_token", to: "kitchen#rotate_display_token", as: :nyk_display_rotate_token
    # Owner-editable flyer print/scan rate, changed inline from Neon's cost dialog.
    patch "flyer_rate", to: "kitchen#update_flyer_rate", as: :nyk_flyer_rate
    # Printer-friendly list of the same N classes the display cycles. Admin-only.
    get "display/print",  to: "kitchen#display_print",  as: :nyk_display_print
    # Beacon the flyer page fires once it renders in a real browser. The GET above
    # is fetched by crawlers and QA scripts too, so the count and the charge hang
    # off this instead.
    post "display/print/opened", to: "kitchen#record_print", as: :nyk_record_print
    # Force a re-scrape of nykitchen.com so a class pulled from the website today
    # stops printing on the flyer. NYK managers only.
    post "classes/refresh", to: "kitchen#refresh_classes", as: :nyk_refresh_classes
    # Trackable QR redirect: logs the scan, then 302s to the real class page.
    # Public (walk-ins scan it with no login); short path so the QR stays dense.
    get "r/:token",       to: "kitchen#scan_redirect",  as: :nyk_scan
    # Class packets: a per-class bundle (recipes + equipment + pull sheet),
    # created/attached from Sam's list page.
    post "equipment_tags/hide", to: "kitchen_packets#hide_equipment", as: :nyk_hide_equipment_tag
    get "packets/open",      to: "kitchen_packets#open",   as: :open_nyk_packet
    get "packets/active_builds", to: "kitchen_packets#active_builds", as: :nyk_active_builds
    get "packets/new",       to: "kitchen_packets#new",    as: :new_nyk_packet
    post "packets",           to: "kitchen_packets#create", as: :nyk_packets
    get "packets/:id/edit",  to: "kitchen_packets#edit",   as: :edit_nyk_packet
    post "packets/:id/regenerate", to: "kitchen_packets#regenerate", as: :regenerate_nyk_packet
    patch "packets/:id",       to: "kitchen_packets#update", as: :nyk_packet
    patch "packets/:id/equipment", to: "kitchen_packets#update_equipment", as: :nyk_packet_equipment
    patch "packets/:id/purchase_equipment", to: "kitchen_packets#update_purchase_equipment", as: :nyk_packet_purchase_equipment
    post "packets/:id/suggest_equipment", to: "kitchen_packets#suggest_equipment", as: :nyk_suggest_equipment
    delete "packets/:id",       to: "kitchen_packets#destroy"
    get "packets/:id/print", to: "kitchen_packets#print",  as: :print_nyk_packet
    # The recipe/packet library: browse + search every packet on its own page
    # (moved off the bottom of the new-packet page as the library grew).
    get "recipes",            to: "kitchen_packets#library", as: :nyk_recipes
    # Legacy redirects: old /handouts URLs.
    get "handouts/new",       to: redirect("/%{workspace_slug}/packets/new")
    get "handouts/:id/edit",  to: redirect("/%{workspace_slug}/packets/%{id}/edit")
    get "handouts/:id/print", to: redirect("/%{workspace_slug}/packets/%{id}/print")
    get "handouts/:id",       to: redirect("/%{workspace_slug}/packets/%{id}/edit")
    # /<slug>/social renders the workspace's social composer in-place so the
    # four agent URLs on the hub all read /<slug>/<agent>. Shares
    # WorkspacesController#social, which reads :workspace_slug when :slug is absent.
    get "social", to: "workspaces#social", as: :nyk_social
    get "digests/:id", to: "kitchen#digest", as: :nyk_digest
    get "smoke_runs/:id/page_source", to: "kitchen#download_smoke_page_source", as: :nyk_smoke_page_source
    get "smoke_runs/:id/trace", to: "kitchen#download_smoke_trace", as: :nyk_smoke_trace
    # Managers email a failed run's report (error + console + artifact links) to
    # any address, e.g. an outside developer. Metered usage event per send.
    post "smoke_runs/:id/report", to: "kitchen#send_smoke_report", as: :nyk_send_smoke_report
    post "social_post_log", to: "kitchen#social_post_log"
    post "enhance_post", to: "kitchen#enhance_post"
    post "send_to_workspace", to: "kitchen#send_to_workspace"
    get "billing",      to: "nyk_billing#show",        as: :nyk_billing
    patch "billing/rate",    to: "nyk_billing#update_rate",    as: :nyk_billing_rate
    patch "billing/pricing", to: "nyk_billing#update_pricing", as: :nyk_billing_pricing
    patch "billing/model",   to: "nyk_billing#update_model",   as: :nyk_billing_model
    patch "billing/auto_recipe", to: "nyk_billing#update_auto_recipe", as: :nyk_billing_auto_recipe
    patch "billing/invoices/:id/pay", to: "nyk_billing#mark_invoice_paid", as: :nyk_billing_invoice_pay
    post "trigger_smoke", to: "kitchen#trigger_smoke", as: :nyk_trigger_smoke
    patch "agents/:kind",   to: "kitchen#rename_agent", as: :nyk_rename_agent
    patch "agents/:kind/avatar", to: "kitchen#update_agent_avatar", as: :nyk_agent_avatar

    # NY Kitchen storage-room alcohol inventory. Lora scans cases IN, Chris scans
    # bottles OUT; on-hand is the running Σ (in − out). All actions require
    # sign-in (no public access); enforce_workspace_scope already lets NYK
    # workspace members reach /nykitchen/*. /items/new must precede /items/:id.
    get "inventory",            to: "inventory#index",           as: :nyk_inventory
    get "inventory/receive",    to: "inventory#receive",         as: :nyk_inventory_receive
    get "inventory/remove",     to: "inventory#remove",          as: :nyk_inventory_remove
    get "inventory/lookup",     to: "inventory#lookup",          as: :nyk_inventory_lookup
    get "inventory/import",     to: "inventory#import",          as: :nyk_inventory_import
    post "inventory/import",     to: "inventory#import_upload"
    post "inventory/movements",  to: "inventory#create_movement", as: :nyk_inventory_movements
    get "inventory/items/new",  to: "inventory#new_item",        as: :new_nyk_inventory_item
    post "inventory/items",      to: "inventory#create_item",     as: :nyk_inventory_items
    get "inventory/items/:id",      to: "inventory#show_item",   as: :nyk_inventory_item
    get "inventory/items/:id/edit", to: "inventory#edit_item",   as: :edit_nyk_inventory_item
    patch "inventory/items/:id",      to: "inventory#update_item"
    # Photo + price capture log -> monthly CSV (separate from the scan in/out ledger).
    get "inventory/captures",        to: "inventory#captures",        as: :nyk_inventory_captures
    post "inventory/captures",        to: "inventory#create_capture"
    get "inventory/captures/export", to: "inventory#captures_export", as: :nyk_inventory_captures_export
    delete "inventory/captures/:id",  to: "inventory#destroy_capture", as: :nyk_inventory_capture
  end

  get "crypto", to: "crypto#index", as: :crypto
  resources :news_articles, only: [ :index ], path: "news"
  # Pulse retired 2026-05-28: public route, controller, and views removed.
  # Old /pulse and /newsletter URLs now 404 (intentional). The admin Posts and
  # Videos managers were retired 2026-06-14; Post/Video models remain.
  resources :subscribers, only: [ :create ]
  get "soft_gate", to: "soft_gates#show", as: :soft_gate

  get "notifications", to: "notifications#index"

  resources :workspaces, only: [ :index, :new, :create, :show, :update, :destroy ], param: :slug do
    member do
      get  :social
      get  "billing",                           to: "workspace_billing#show",             as: :billing
      post "billing/pricing",                   to: "workspace_billing#update_pricing",   as: :billing_pricing
      post "billing/model",                     to: "workspace_billing#update_model",     as: :billing_model
      post "billing/invoices/:invoice_id/paid", to: "workspace_billing#mark_invoice_paid", as: :billing_invoice_paid
      post :refresh_metrics
      post :toggle_pricing
      post :toggle_grocery_prices
      patch :social_tabs
      patch "listening_topics", action: :update_listening_topics
      get :connect_chats
    end
    resources :invitations, only: [ :create, :destroy ], controller: "workspace_invitations"
    resources :memberships, only: [ :destroy ], controller: "workspace_memberships"
    resources :social_accounts, only: [ :destroy ]
    resources :social_leads, only: [ :destroy ] do
      member do
        patch :dismiss
        patch :mark_sent
      end
    end
    resources :posts, only: [ :create, :destroy ], controller: "workspace_posts" do
      member do
        post :retry
      end
    end
    post "drafts/suggest", to: "workspace_drafts#suggest", as: :draft_suggest
    post "drafts/from_image", to: "workspace_drafts#from_image", as: :draft_from_image
    post "ai_chat", to: "workspace_ai_chats#create", as: :ai_chat
    resources :drafts, only: [ :create, :edit, :update, :destroy ], controller: "workspace_drafts" do
      member do
        post :publish
        post :rewrite
      end
    end
    post "oauth/x/connect", to: "oauth/x#connect", as: :oauth_x_connect
    post "oauth/threads/connect",  to: "oauth/threads#connect",  as: :oauth_threads_connect
    post "oauth/facebook/connect", to: "oauth/facebook#connect", as: :oauth_facebook_connect
    resource :bluesky_account, only: [ :new, :create ]
  end
  get  "invitations/:token",        to: "workspace_invitations#show",   as: :workspace_invitation_view
  post "invitations/:token/accept", to: "workspace_invitations#accept", as: :workspace_invitation_accept
  get  "oauth/x/callback",          to: "oauth/x#callback",             as: :oauth_x_callback
  get  "oauth/threads/callback",    to: "oauth/threads#callback",       as: :oauth_threads_callback
  get  "oauth/facebook/callback",   to: "oauth/facebook#callback",      as: :oauth_facebook_callback

  namespace :api do
    namespace :v1 do
      resources :jobs, only: [ :create ]
      resources :scrapers, only: [ :update ]
      # Apply queue for the Mac-Mini Playwright runner (Phase 2).
      resources :apply_requests, only: [ :index, :update ] do
        # The Mac-Mini daemon clears the "Run now" flag once it acts on it.
        delete :run_request, on: :collection, action: :clear_run_request
      end
      patch "agents/:name/status", to: "agents#update_status", as: :agent_status
      get "agents/statuses", to: "agents#statuses"
      put "agents/:slug/profile", to: "agents#update_profile", as: :agent_profile
      post "agents/:slug/memories", to: "agents#add_memory", as: :agent_memories
      post "telegram/webhook", to: "telegram_webhook#create"
      post "deploy", to: "deploys#create"
      get "chat/pending", to: "chat#pending"
      patch "chat/:id/ack", to: "chat#ack", as: :chat_ack
      post "chat/reply", to: "chat#reply"
      get "stats/users", to: "stats#users"
      resources :smoke_runs, only: [ :create, :update ] do
        member do
          put :video
        end
      end
      resources :kitchen_snapshots, only: [ :create ] do
        collection do
          get :upcoming
        end
      end
      post "nyk/filter_expanded", to: "nyk_metrics#filter_expanded", as: :nyk_filter_expanded
      resources :device_tokens, only: [ :create ]
      resources :notifications, only: [ :create ]
      post "badge/clear", to: "badges#clear"
      get  "badge/peek",  to: "badges#peek"
    end
  end

  namespace :admin do
    get "dashboard", to: "dashboard#index"
    resources :scrapers do
      member do
        post :run
      end
    end
    resources :users, only: [ :index, :destroy ]
    get "track", to: "track#index", as: :track
    get    "finance",              to: "finance#index",           as: :finance
    post   "finance/import",       to: "finance#import",          as: :finance_import
    patch  "finance/expenses/:id", to: "finance#update_expense",  as: :finance_expense
    post   "finance/revenues",     to: "finance#create_revenue",  as: :finance_revenues
    delete "finance/revenues/:id", to: "finance#destroy_revenue", as: :finance_revenue
    get  "plan",        to: "plan#show",   as: :plan
    post "plan/toggle", to: "plan#toggle", as: :plan_toggle
    get "visitors/map", to: "visitors#map"
    resources :agents, param: :slug
    get "kitchen", to: redirect("/nykitchen", status: 301)
    post "kitchen/trigger_smoke", to: "kitchen#trigger_smoke", as: :trigger_smoke
    resources :smoke_runs, only: [ :destroy ]
    resources :notifications, only: [ :index, :update, :destroy ] do
      collection do
        post :mark_all_read
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
