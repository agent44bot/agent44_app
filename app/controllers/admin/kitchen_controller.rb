module Admin
  class KitchenController < BaseController
    def trigger_smoke
      token = ENV["GITHUB_PAT"]
      if token.blank?
        redirect_to nykitchen_path, alert: "GITHUB_PAT not configured"
        return
      end

      uri = URI("https://api.github.com/repos/agent44bot/agent44_app/dispatches")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Accept"] = "application/vnd.github+json"
      req["Content-Type"] = "application/json"
      req.body = { event_type: "smoke-nyk" }.to_json

      res = http.request(req)

      if res.is_a?(Net::HTTPSuccess) || res.code == "204"
        redirect_to nykitchen_path, notice: "Smoke test triggered — results will appear shortly"
      else
        redirect_to nykitchen_path, alert: "GitHub dispatch failed (#{res.code})"
      end
    rescue => e
      redirect_to nykitchen_path, alert: "Error: #{e.message}"
    end
  end
end
