class ApplicationController < ActionController::Base
  # CSRF is ON (Devise + Turbo). Api::V1::BaseController overrides the strategy for JSON clients.
end
