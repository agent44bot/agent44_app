# Preview at http://localhost:3000/rails/mailers/echo_mailer/new_leads
class EchoMailerPreview < ActionMailer::Preview
  def new_leads
    ws = Workspace.find_by(slug: "nykitchen") || Workspace.first
    return unless ws

    leads = ws.social_leads.recent.limit(4).to_a
    return if leads.empty?

    EchoMailer.new_leads(workspace: ws, leads: leads, recipient: "preview@example.com", membership: ws.memberships.first)
  end
end
