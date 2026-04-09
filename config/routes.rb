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
      get "stats/users", to: "stats#users"
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
    resources :notifications, only: [:index, :update, :destroy] do
      collection do
        post :mark_all_read
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
