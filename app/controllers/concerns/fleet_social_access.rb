# Gates Fleet Social entry: site admins always pass, plus any user who is
# a member of at least one workspace (so invitees who accepted can use the
# product). Per-workspace authorization (require_member / require_admin /
# require_writer) still gates each workspace's actions inside the resource
# controllers. Workspace creation stays site-admin-only via
# WorkspacesController#require_site_admin.
module FleetSocialAccess
  extend ActiveSupport::Concern

  included do
    before_action :require_fleet_social_access
  end

  private

  def require_fleet_social_access
    user = Current.session&.user
    return if user&.admin?
    return if user&.workspace_memberships&.exists?
    redirect_to root_path, alert: "Workspaces are by invitation — ask an admin to invite you."
  end
end
