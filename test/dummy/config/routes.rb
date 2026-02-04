Rails.application.routes.draw do
  mount ActionCable.server => "/cable"
  mount Rbrun::Engine => "/rbrun"
end
