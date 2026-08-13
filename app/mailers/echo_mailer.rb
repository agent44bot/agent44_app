class EchoMailer < ApplicationMailer
  HOST = "https://agent44labs.com".freeze

  # Emailed by SocialListenJob when a listening run turns up new conversations
  # worth joining. One email per run (not one per lead), so a run that finds
  # four leads sends one digest, the same way the push does. `leads` are
  # SocialLeads; nothing here posts anything, the email just shows the post,
  # Echo's suggested reply, and a link to the Echo page to act on it.
  def new_leads(workspace:, leads:, recipients:)
    @workspace = workspace
    @leads     = leads.sort_by { |l| [ -l.score.to_i, -l.posted_at.to_i ] }
    @echo_url  = HOST + echo_path(workspace)

    top     = @leads.first
    count   = @leads.size
    subject =
      if count == 1
        "Echo: 1 new conversation for #{workspace.name} (#{top.platform_label} · #{top.score})"
      else
        "Echo: #{count} new conversations for #{workspace.name}"
      end

    mail(to: recipients, subject: subject)
  end

  private

  # NY Kitchen's Echo page lives at the vanity /nykitchen/social; every other
  # workspace uses the generic /workspaces/:slug/social.
  def echo_path(workspace)
    routes = Rails.application.routes.url_helpers
    workspace.slug == "nykitchen" ? routes.nyk_social_path : routes.social_workspace_path(workspace.slug)
  end
end
