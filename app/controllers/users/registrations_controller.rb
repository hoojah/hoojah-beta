class Users::RegistrationsController < Devise::RegistrationsController
  invisible_captcha only: [:create], honeypot: :subtitle
  before_action :configure_permitted_parameters

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:username, :full_name])
    devise_parameter_sanitizer.permit(:account_update, keys: [:username, :full_name])
  end
end
