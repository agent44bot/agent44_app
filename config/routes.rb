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
  get "email_verification", to: "email_verifications#show", as: :email_verification
  post "email_verification/resend", to: "email_verifications#resend", as: :resend_email_verification

  resources :jobs, only: [ :index, :show ] do
    collection do
      get :globe
      get :today
      get :for_me
    end
    member do
      post :apply_kit
    end
    resource :saved_job, only: [ :create, :destroy ] do
      post :toggle_applied, on: :member
    end
    resource :hidden_job, only: [ :create, :destroy ]
  end
  resources :saved_jobs, only: [ :index ]
  get "nykitchen",        to: "kitchen#hub"
  get "nykitchen/guide",  to: "kitchen#guide", as: :nyk_guide
  get "nykitchen/list",   to: "kitchen#list", as: :nyk_list
  get "nykitchen/grocery", to: "kitchen#grocery", as: :nyk_grocery
  post "nykitchen/grocery/receipts", to: "kitchen#upload_receipt", as: :nyk_grocery_receipts
  patch "nykitchen/grocery/portion", to: "kitchen#update_portion", as: :nyk_grocery_portion
  get    "nykitchen/prices",     to: "kitchen#prices",       as: :nyk_prices
  patch  "nykitchen/prices/:id", to: "kitchen#update_price", as: :nyk_price
  delete "nykitchen/prices/:id", to: "kitchen#destroy_price"
  get "nykitchen/test",   to: "kitchen#test", as: :nyk_test
  get "nykitchen/data",   to: "kitchen#data", as: :nyk_data
  get   "nykitchen/analyst", to: "kitchen#analyst", as: :nyk_analyst
  patch "nykitchen/analyst/subscription", to: "kitchen#update_analyst_subscription", as: :nyk_analyst_subscription
  # Admin-only live preview of the weekly Agent Team Report (real data, same
  # builder as the real send). 404s for non-admins. See kitchen#report_preview.
  get   "nykitchen/analyst/report", to: "kitchen#report_preview", as: :nyk_report_preview
  # On-demand report for NY Kitchen managers: generate a fresh copy (POST so it
  # isn't re-run on refresh/prefetch); it emails a copy to the logged-in user
  # only. Metered action.
  post  "nykitchen/analyst/report/generate", to: "kitchen#generate_report", as: :nyk_generate_report
  get  "nykitchen/ask",          to: "kitchen#ask",                as: :nyk_ask
  post "nykitchen/ask/message",  to: "kitchen#ask_message",        as: :nyk_ask_message
  post "nykitchen/ask/examples", to: "kitchen#update_ask_examples", as: :nyk_ask_examples
  # Public, no-auth screen for the tasting-room display monitor.
  # Cycles currently-available classes; auto-refreshes periodically.
  get  "nykitchen/display", to: "kitchen#display", as: :nyk_display
  # Liveness ping from the live screen (private mode only). Records last-seen
  # so the hub's Display Agent dot reflects whether the TV is actually on.
  post "nykitchen/display/heartbeat", to: "kitchen#display_heartbeat", as: :nyk_display_heartbeat
  # Display Agent admin: hub-card detail page with config form.
  get   "nykitchen/display/settings", to: "kitchen#display_settings",        as: :nyk_display_settings
  patch "nykitchen/display/settings", to: "kitchen#update_display_settings"
  post  "nykitchen/display/rotate_token", to: "kitchen#rotate_display_token", as: :nyk_display_rotate_token
  # Printer-friendly list of the same N classes the display cycles. Admin-only.
  get   "nykitchen/display/print",  to: "kitchen#display_print",  as: :nyk_display_print
  # Class packets: a per-class bundle (recipes + equipment + pull sheet),
  # created/attached from Sam's list page.
  post   "nykitchen/equipment_tags/hide", to: "kitchen_packets#hide_equipment", as: :nyk_hide_equipment_tag
  get    "nykitchen/packets/open",      to: "kitchen_packets#open",   as: :open_nyk_packet
  get    "nykitchen/packets/new",       to: "kitchen_packets#new",    as: :new_nyk_packet
  post   "nykitchen/packets",           to: "kitchen_packets#create", as: :nyk_packets
  get    "nykitchen/packets/:id/edit",  to: "kitchen_packets#edit",   as: :edit_nyk_packet
  post   "nykitchen/packets/:id/regenerate", to: "kitchen_packets#regenerate", as: :regenerate_nyk_packet
  patch  "nykitchen/packets/:id",       to: "kitchen_packets#update", as: :nyk_packet
  patch  "nykitchen/packets/:id/equipment", to: "kitchen_packets#update_equipment", as: :nyk_packet_equipment
  post   "nykitchen/packets/:id/suggest_equipment", to: "kitchen_packets#suggest_equipment", as: :nyk_suggest_equipment
  delete "nykitchen/packets/:id",       to: "kitchen_packets#destroy"
  get    "nykitchen/packets/:id/print", to: "kitchen_packets#print",  as: :print_nyk_packet
  # Legacy redirects: old /handouts URLs and the removed /recipes library page
  # (search/reuse now lives at the bottom of the new-packet page).
  get "nykitchen/recipes",            to: redirect("/nykitchen/list")
  get "nykitchen/handouts/new",       to: redirect("/nykitchen/packets/new")
  get "nykitchen/handouts/:id/edit",  to: redirect("/nykitchen/packets/%{id}/edit")
  get "nykitchen/handouts/:id/print", to: redirect("/nykitchen/packets/%{id}/print")
  get "nykitchen/handouts/:id",       to: redirect("/nykitchen/packets/%{id}/edit")
  # /nykitchen/social renders the NYK workspace's social composer in-place
  # so the four agent URLs on the hub all read /nykitchen/<agent>. Shares
  # WorkspacesController#social by baking the slug in as a default param.
  get "nykitchen/social", to: "workspaces#social", defaults: { slug: "nykitchen" }, as: :nyk_social
  get "nykitchen/digests/:id", to: "kitchen#digest", as: :nyk_digest
  get "nykitchen/smoke_runs/:id/page_source", to: "kitchen#download_smoke_page_source", as: :nyk_smoke_page_source
  get "nykitchen/smoke_runs/:id/trace", to: "kitchen#download_smoke_trace", as: :nyk_smoke_trace
  # Managers email a failed run's report (error + console + artifact links) to
  # any address, e.g. an outside developer. Metered usage event per send.
  post "nykitchen/smoke_runs/:id/report", to: "kitchen#send_smoke_report", as: :nyk_send_smoke_report
  post "nykitchen/social_post_log", to: "kitchen#social_post_log"
  post "nykitchen/enhance_post", to: "kitchen#enhance_post"
  post "nykitchen/send_to_workspace", to: "kitchen#send_to_workspace"
  get   "nykitchen/billing",      to: "nyk_billing#show",        as: :nyk_billing
  patch "nykitchen/billing/rate",    to: "nyk_billing#update_rate",    as: :nyk_billing_rate
  patch "nykitchen/billing/pricing", to: "nyk_billing#update_pricing", as: :nyk_billing_pricing
  patch "nykitchen/billing/model",   to: "nyk_billing#update_model",   as: :nyk_billing_model
  patch "nykitchen/billing/auto_recipe", to: "nyk_billing#update_auto_recipe", as: :nyk_billing_auto_recipe
  patch "nykitchen/billing/invoices/:id/pay", to: "nyk_billing#mark_invoice_paid", as: :nyk_billing_invoice_pay
  post "nykitchen/trigger_smoke", to: "kitchen#trigger_smoke", as: :nyk_trigger_smoke
  patch "nykitchen/agents/:kind",   to: "kitchen#rename_agent", as: :nyk_rename_agent
  patch "nykitchen/agents/:kind/avatar", to: "kitchen#update_agent_avatar", as: :nyk_agent_avatar

  # NY Kitchen storage-room alcohol inventory. Lora scans cases IN, Chris scans
  # bottles OUT; on-hand is the running Σ (in − out). All actions require
  # sign-in (no public access); enforce_workspace_scope already lets NYK
  # workspace members reach /nykitchen/*. /items/new must precede /items/:id.
  get   "nykitchen/inventory",            to: "inventory#index",           as: :nyk_inventory
  get   "nykitchen/inventory/receive",    to: "inventory#receive",         as: :nyk_inventory_receive
  get   "nykitchen/inventory/remove",     to: "inventory#remove",          as: :nyk_inventory_remove
  get   "nykitchen/inventory/lookup",     to: "inventory#lookup",          as: :nyk_inventory_lookup
  get   "nykitchen/inventory/import",     to: "inventory#import",          as: :nyk_inventory_import
  post  "nykitchen/inventory/import",     to: "inventory#import_upload"
  post  "nykitchen/inventory/movements",  to: "inventory#create_movement", as: :nyk_inventory_movements
  get   "nykitchen/inventory/items/new",  to: "inventory#new_item",        as: :new_nyk_inventory_item
  post  "nykitchen/inventory/items",      to: "inventory#create_item",     as: :nyk_inventory_items
  get   "nykitchen/inventory/items/:id",      to: "inventory#show_item",   as: :nyk_inventory_item
  get   "nykitchen/inventory/items/:id/edit", to: "inventory#edit_item",   as: :edit_nyk_inventory_item
  patch "nykitchen/inventory/items/:id",      to: "inventory#update_item"
  # Photo + price capture log -> monthly CSV (separate from the scan in/out ledger).
  get  "nykitchen/inventory/captures",        to: "inventory#captures",        as: :nyk_inventory_captures
  post "nykitchen/inventory/captures",        to: "inventory#create_capture"
  get  "nykitchen/inventory/captures/export", to: "inventory#captures_export", as: :nyk_inventory_captures_export
  delete "nykitchen/inventory/captures/:id",  to: "inventory#destroy_capture", as: :nyk_inventory_capture

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
      post "billing/invoices/:invoice_id/paid", to: "workspace_billing#mark_invoice_paid", as: :billing_invoice_paid
      post :refresh_metrics
      post :toggle_pricing
      post :toggle_grocery_prices
    end
    resources :invitations, only: [ :create, :destroy ], controller: "workspace_invitations"
    resources :social_accounts, only: [ :destroy ]
    resources :posts, only: [ :create, :destroy ], controller: "workspace_posts"
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
      patch "agents/:name/status", to: "agents#update_status", as: :agent_status
      get "agents/statuses", to: "agents#statuses"
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
    resources :agents, except: [ :show ]
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
