class PagesController < ApplicationController
  allow_unauthenticated_access

  def home
    # NY Kitchen smoke test case study data
    nyk_runs = SmokeTestRun.nyk.recent
    @nyk_latest_run = nyk_runs.first
    @nyk_total_runs = nyk_runs.count
    @nyk_pass_rate = nyk_runs.any? ? (nyk_runs.where(status: "passed").count.to_f / nyk_runs.count * 100).round : nil
    @nyk_total_cost = nyk_runs.sum(:cost_dollars)
    @can_see_nyk_pricing = Workspace.find_by(slug: "nykitchen")&.pricing_visible_for?(Current.user) || false
  end

  def privacy
  end
end
