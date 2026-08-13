class EchoMailer < ApplicationMailer
  HOST = "https://agent44labs.com".freeze

  # Echo's daily 3pm email: the conversations it found since yesterday's send,
  # with the post, Echo's "why", the suggested reply, and links to act on it.
  # Sent by EchoDailyEmailJob, one email per recipient (not one to-all) so each
  # carries its own unsubscribe link and nobody sees anyone else's address.
  #
  # `membership` is the recipient's WorkspaceMembership when they're a member,
  # which is what makes the one-click unsubscribe possible; extra addresses
  # configured by hand (Setting "social_listen:notify_emails") pass nil and get
  # the same email minus the link.
  def new_leads(workspace:, leads:, recipient:, membership: nil)
    @workspace = workspace
    @leads     = leads.sort_by { |l| [ -l.score.to_i, -l.posted_at.to_i ] }
    @echo_url  = HOST + echo_path(workspace)
    @unsubscribe_url = membership && HOST + Rails.application.routes.url_helpers.echo_email_unsubscribe_path(membership.echo_unsubscribe_token)
    @settings_url    = "#{HOST}/settings"

    # Let Gmail/Apple Mail show their own unsubscribe button. One-Click posts
    # straight to the same endpoint the in-email link confirms through.
    if @unsubscribe_url
      headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
      headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    end

    top     = @leads.first
    count   = @leads.size
    subject =
      if count == 1
        "Echo: 1 new conversation for #{workspace.name} (#{top.platform_label} · #{top.score})"
      else
        "Echo: #{count} new conversations for #{workspace.name}"
      end

    mail(to: recipient, subject: subject)
  end

  private

  # NY Kitchen's Echo page lives at the vanity /nykitchen/social; every other
  # workspace uses the generic /workspaces/:slug/social.
  def echo_path(workspace)
    routes = Rails.application.routes.url_helpers
    workspace.slug == "nykitchen" ? routes.nyk_social_path : routes.social_workspace_path(workspace.slug)
  end
end
