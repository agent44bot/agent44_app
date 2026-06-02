class NotificationsController < ApplicationController
  def index
    user = Current.user
    @notifications = user.notifications.recent.limit(50)
    @unread_count = user.notifications.unread.count
    # Give NYK members (and admins/reviewer) a prominent way out of this page —
    # a sellout push that lands here would otherwise dead-end. Job-seekers and
    # other signed-in users don't see an NYK button.
    @show_nyk_cta = user.admin? || user.reviewer? ||
                    Workspace.find_by(slug: "nykitchen")&.member?(user) || false
    user.notifications.unread.update_all(read_at: Time.current)
  end
end
