module Admin
  class UsersController < BaseController
    def index
      @users = User.includes(:sessions).order(created_at: :desc)
    end

    # The "Feedback" switch: whether this user sees the Feedback button and
    # can send feedback (which becomes input to the feedback agent).
    def toggle_feedback_access
      return if forbid_impersonation!
      user = User.find(params[:id])
      user.update!(feedback_access: !user.feedback_access?)
      redirect_to admin_users_path,
                  notice: "Feedback #{user.feedback_access? ? 'on' : 'off'} for #{user.display_identifier}."
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
