module Admin
  class BaseController < ApplicationController
    layout "admin"
    before_action :require_admin

    private

    def require_admin
      unless Current.session&.user&.admin?
        redirect_to root_path, alert: "Not authorized."
      end
    end
  end
end
