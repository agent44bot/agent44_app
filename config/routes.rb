Rails.application.routes.draw do
  root "pages#home"

  resource :session do
    post :challenge, on: :collection
  end
  resource :registration, only: [:new, :create]
  resources :passwords, param: :token
  get "email_verification", to: "email_verifications#show", as: :email_verification
  post "email_verification/resend", to: "email_verifications#resend", as: :resend_email_verification

  resources :jobs, only: [:index, :show] do
    resource :saved_job, only: [:create, :destroy] do
      post :toggle_applied, on: :member
    end
  end
  resources :saved_jobs, only: [:index]
  resources :posts, only: [:index, :show], path: "newsletter"
  resources :videos, only: [:index, :show]
  resources :subscribers, only: [:create]

  namespace :api do
    namespace :v1 do
      resources :jobs, only: [:create]
    end
  end

  namespace :admin do
    get "dashboard", to: "dashboard#index"
    resources :posts
    resources :videos
    resources :users, only: [:index]
    get "visitors/map", to: "visitors#map"
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
