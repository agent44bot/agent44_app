# Gates Fleet Social to site admins only during the dogfood phase. We're
# validating workspaces / X / Bluesky / AI drafts via @agent44bot before
# opening the product to general signup or kitchen_customer roles like
# Laura. See memory: project-fleet-social-dogfood-first.
#
# When we're ready to open up, replace .admin? with a broader predicate
# (e.g. admin? || fleet_social_invited?) and exempt the invitation
# accept flow so invited non-admins can land in their workspace.
module FleetSocialAccess
  extend ActiveSupport::Concern

  included do
    before_action :require_fleet_social_access
  end

  private

  def require_fleet_social_access
    return if Current.session&.user&.admin?
    redirect_to root_path, alert: "Workspaces are in private beta — admin access only for now."
  end
end
