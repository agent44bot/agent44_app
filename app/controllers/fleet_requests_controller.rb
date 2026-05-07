class FleetRequestsController < ApplicationController
  def create
    user = Current.session.user
    services = Array(params[:services]).map(&:to_s).select { |s| FleetRequest::SERVICES.key?(s) }
    note = params[:note].to_s.strip[0, 500]

    request = user.fleet_requests.create!(
      services: services.join(","),
      notes:    note.presence,
      status:   "pending"
    )

    notify_admins(user, request)

    redirect_to root_path, notice: "Got it — Rich will reach out within one business day."
  end

  private

  def notify_admins(user, request)
    services_str = request.services_labels.presence&.join(", ") || "(no services picked yet)"
    body = "From: #{user.email_address}\nWants: #{services_str}"
    body += "\nNote: #{request.notes}" if request.notes.present?

    admins = User.where(role: "admin").where.not(email_address: nil)
    Notification.notify!(
      level:    "info",
      source:   "fleet_request",
      title:    "Fleet onboarding request",
      body:     body,
      telegram: true,
      apns:     false
    )
    admins.each do |admin|
      Notification.notify!(
        level:     "info",
        source:    "fleet_request",
        title:     "Fleet request: #{user.email_address}",
        body:      services_str,
        telegram:  false,
        apns:      true,
        apns_url:  "/admin/dashboard",
        apns_user: admin
      )
    end
  end
end
