# One-click unsubscribe from Echo's daily 3pm conversations email, reached from
# the link in the email itself. No sign-in: the signed token in the URL names
# the membership, so a recipient who can't remember their password can still
# stop the email (and only their own).
#
# GET shows a confirm page and POST does the turn-off, on purpose: mail scanners
# and link prefetchers follow GETs, and a prefetched unsubscribe would silently
# mute someone. The email also advertises the POST endpoint via List-Unsubscribe
# for clients that offer their own unsubscribe button.
class EchoEmailSubscriptionsController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :verify_authenticity_token, only: :destroy # List-Unsubscribe POSTs carry no CSRF token
  skip_before_action :enforce_workspace_scope # signed-in members must land here, not be bounced to /workspaces
  before_action :set_membership

  def show
  end

  def destroy
    @membership.update!(echo_email_enabled: false)
    render :destroy
  end

  private

  def set_membership
    @membership = WorkspaceMembership.find_by_echo_unsubscribe_token(params[:token])
    render :invalid, status: :not_found unless @membership
  end
end
