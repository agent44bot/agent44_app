Rails.application.routes.draw do
  root "pages#home"

  resource :session do
    post :challenge, on: :collection
  end
  resources :passwords, param: :token

  resources :jobs, only: [:index, :show]
  resources :posts, only: [:index, :show], path: "newsletter"
  resources :videos, only: [:index, :show]
  resources :subscribers, only: [:create]

  namespace :api do
    namespace :v1 do
      resources :jobs, only: [:create]
    end
  end

  namespace :admin do
    resources :posts
    resources :videos
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
