Rails.application.routes.draw do
  devise_for :users,
    controllers: { registrations: 'users/registrations' },
    path: '',
    path_names: { sign_in: 'login', sign_out: 'logout', sign_up: 'signup' }

  namespace :api do
    namespace :v1 do
      get 'hoojah/index', to: 'hujahs#index'
      post 'hoojah/create', to: 'hujahs#create'
      get '/hoojah/:slug', to: 'hujahs#show'
      delete '/hoojah/destroy/:slug', to: 'hujahs#destroy'
      get '/hoojah/new', to: 'hujahs#new'

      post 'votes/create', to: 'votes#create'

      get '/:username', to: 'users#show'
      post ':username/update', to: 'users#update'

      post 'flags/create', to: 'flags#create'

      get '/:username/notifications', to: 'notifications#index'
      put '/:username/notifications/:id', to: 'notifications#update'
      delete '/:username/notifications/:id', to: 'notifications#destroy'
    end
  end

  root 'hujah#index'
end
