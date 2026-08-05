class ApplicationController < ActionController::Base
  # CSRF is ON (Devise + Turbo). Api::V1::BaseController overrides the strategy for JSON clients.

  # Pagy ~> 43.6 exposes the `pagy(:countless, collection)` paginator via this mixin
  # (the reworked replacement for the classic `Pagy::Backend`).
  include Pagy::Method
end
