module Admin
  class UsersController < BaseController
    def index
      @users = User.includes(:sessions).order(created_at: :desc)
    end

    # Hard-delete a user from the admin Users page. The User has_many
    # associations cascade workspace memberships, owned workspaces, sent
    # invitations, drafts, posts, etc., so deleting here unwinds the
    # whole user graph in one shot.
    def destroy
      return if forbid_impersonation!
      user = User.find(params[:id])
      if user.admin?
        redirect_to admin_users_path, alert: "Refusing to delete an admin user."
      elsif user.id == Current.real_user&.id
        redirect_to admin_users_path, alert: "You can't delete yourself."
      else
        label = user.display_identifier
        user.destroy!
        redirect_to admin_users_path, notice: "Deleted #{label}."
      end
    end
  end
end
