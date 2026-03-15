module Admin
  class UsersController < BaseController
    def index
      @users = User.includes(:sessions).order(created_at: :desc)
    end
  end
end
