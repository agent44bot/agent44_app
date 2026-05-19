Rails.application.routes.draw do
  root "pages#home"
  get "lab", to: "pages#lab"
  get "privacy", to: "pages#privacy"

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
  resource :settings, only: [ :show, :destroy ] do
    post  :verify_password
    patch :update_email
    patch :update_name
  end
  get "email_verification", to: "email_verifications#show", as: :email_verification
  post "email_verification/resend", to: "email_verifications#resend", as: :resend_email_verification

  resources :jobs, only: [ :index, :show ] do
    collection do
      get :globe
      get :today
    end
    resource :saved_job, only: [ :create, :destroy ] do
      post :toggle_applied, on: :member
    end
    resource :hidden_job, only: [ :create, :destroy ]
  end
  resources :saved_jobs, only: [ :index ]
  get "nykitchen",        to: "kitchen#hub"
  get "nykitchen/list",   to: "kitchen#list", as: :nyk_list
  get "nykitchen/test",   to: "kitchen#test", as: :nyk_test
  get "nykitchen/data",   to: "kitchen#data", as: :nyk_data
  # /nykitchen/social renders the NYK workspace's social composer in-place
  # so the four agent URLs on the hub all read /nykitchen/<agent>. Shares
  # WorkspacesController#social by baking the slug in as a default param.
  get "nykitchen/social", to: "workspaces#social", defaults: { slug: "nykitchen" }, as: :nyk_social
  get "nykitchen/digests/:id", to: "kitchen#digest", as: :nyk_digest
  get "nykitchen/smoke_runs/:id/page_source", to: "kitchen#download_smoke_page_source", as: :nyk_smoke_page_source
  get "nykitchen/smoke_runs/:id/trace", to: "kitchen#download_smoke_trace", as: :nyk_smoke_trace
  post "nykitchen/social_post_log", to: "kitchen#social_post_log"
  post "nykitchen/enhance_post", to: "kitchen#enhance_post"
  post "nykitchen/send_to_workspace", to: "kitchen#send_to_workspace"
  get  "nykitchen/billing",                 to: "nyk_billing#show", as: :nyk_billing
  post "nykitchen/trigger_smoke", to: "kitchen#trigger_smoke", as: :nyk_trigger_smoke
  get "crypto", to: "crypto#index", as: :crypto
  resources :news_articles, only: [ :index ], path: "news"
  resources :posts, only: [ :index, :show ], path: "pulse"
  # Permanent redirects from old /newsletter URLs to /pulse
  get "/newsletter", to: redirect("/pulse", status: 301)
  get "/newsletter/*slug", to: redirect("/pulse/%{slug}", status: 301)
  # resources :videos, only: [:index, :show]
  resources :subscribers, only: [ :create ]
  get "soft_gate", to: "soft_gates#show", as: :soft_gate

  get "notifications", to: "notifications#index"

  resources :workspaces, only: [ :index, :new, :create, :show, :update, :destroy ], param: :slug do
    member do
      get  :social
      post :refresh_metrics
      post :toggle_pricing
    end
    resources :invitations, only: [ :create, :destroy ], controller: "workspace_invitations"
    resources :social_accounts, only: [ :destroy ]
    resources :posts, only: [ :create, :destroy ], controller: "workspace_posts"
    post "drafts/suggest", to: "workspace_drafts#suggest", as: :draft_suggest
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
    get "ai_costs",  to: "ai_costs#index"
    resources :posts
    resources :videos
    resources :scrapers do
      member do
        post :run
      end
    end
    resources :users, only: [ :index ]
    get "visitors/map", to: "visitors#map"
    resources :agents, except: [ :show ]
    get "kitchen", to: redirect("/nykitchen", status: 301)
    post "kitchen/trigger_smoke", to: "kitchen#trigger_smoke", as: :trigger_smoke
    resources :smoke_runs, only: [ :destroy ]
    get "chat", to: "chat#index"
    post "chat", to: "chat#create"
    get "chat/messages", to: "chat#messages"
    resources :notifications, only: [ :index, :update, :destroy ] do
      collection do
        post :mark_all_read
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
