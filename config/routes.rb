Rails.application.routes.draw do
  root "pages#home"
  get "lab", to: "pages#lab"

  resource :session do
    post :challenge, on: :collection
  end
  resource :registration, only: [:new, :create]
  resources :passwords, param: :token
  get "email_verification", to: "email_verifications#show", as: :email_verification
  post "email_verification/resend", to: "email_verifications#resend", as: :resend_email_verification

  resources :jobs, only: [:index, :show] do
    collection do
      get :globe
      get :today
    end
    resource :saved_job, only: [:create, :destroy] do
      post :toggle_applied, on: :member
    end
    resource :hidden_job, only: [:create, :destroy]
  end
  resources :saved_jobs, only: [:index]
  get "nykitchen", to: "kitchen#index"
  post "nykitchen/social_post_log", to: "kitchen#social_post_log"
  post "nykitchen/enhance_post", to: "kitchen#enhance_post"
  post "nykitchen/trigger_smoke", to: "kitchen#trigger_smoke", as: :nyk_trigger_smoke
  get "crypto", to: "crypto#index", as: :crypto
  resources :news_articles, only: [:index], path: "news"
  resources :posts, only: [:index, :show], path: "pulse"
  # Permanent redirects from old /newsletter URLs to /pulse
  get "/newsletter", to: redirect("/pulse", status: 301)
  get "/newsletter/*slug", to: redirect("/pulse/%{slug}", status: 301)
  # resources :videos, only: [:index, :show]
  resources :subscribers, only: [:create]
  get "soft_gate", to: "soft_gates#show", as: :soft_gate

  namespace :api do
    namespace :v1 do
      resources :jobs, only: [:create]
      resources :scrapers, only: [:update]
      patch "agents/:name/status", to: "agents#update_status", as: :agent_status
      get "agents/statuses", to: "agents#statuses"
      post "telegram/webhook", to: "telegram_webhook#create"
      post "deploy", to: "deploys#create"
      get "chat/pending", to: "chat#pending"
      patch "chat/:id/ack", to: "chat#ack", as: :chat_ack
      post "chat/reply", to: "chat#reply"
      get "stats/users", to: "stats#users"
      resources :smoke_runs, only: [ :create ] do
        member do
          put :video
        end
      end
      resources :kitchen_snapshots, only: [ :create ] do
        collection do
          get :upcoming
        end
      end
    end
  end

  namespace :admin do
    get "dashboard", to: "dashboard#index"
    resources :posts
    resources :videos
    resources :scrapers do
      member do
        post :run
      end
    end
    resources :users, only: [:index]
    get "visitors/map", to: "visitors#map"
    resources :agents, except: [:show]
    get "kitchen", to: redirect("/nykitchen", status: 301)
    post "kitchen/trigger_smoke", to: "kitchen#trigger_smoke", as: :trigger_smoke
    resources :smoke_runs, only: [ :destroy ]
    get "chat", to: "chat#index"
    post "chat", to: "chat#create"
    get "chat/messages", to: "chat#messages"
    resources :notifications, only: [:index, :update, :destroy] do
      collection do
        post :mark_all_read
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
