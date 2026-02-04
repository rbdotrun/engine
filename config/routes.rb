# frozen_string_literal: true

Rbrun::Engine.routes.draw do
  resources :sandboxes, only: [:index, :create, :show, :destroy] do
    member do
      post :toggle_expose
    end
    resources :logs, only: [:index]
    resources :sessions, only: [:index, :create, :show]
    match "sessions", to: "sessions#options", via: :options
  end

  get "resources", to: "resources#index"
  get "console.js", to: "consoles#show"
  get ":filename", to: "consoles#show", constraints: { filename: /console\.[a-zA-Z0-9_-]+\.js/ }

  root "sandboxes#index"
end
