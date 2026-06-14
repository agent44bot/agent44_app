class PagesController < ApplicationController
  allow_unauthenticated_access

  MOCK_AGENT_ROLES = [
    "Smoke Runner", "QA Engineer", "Linter", "Profiler", "Log Watcher",
    "Crawler", "Replayer", "Deploy Bot", "DB Migrator", "API Monitor"
  ].freeze

  def home
    # The personalized agent list (Vlad / Ripley / …) used to be admin-only on
    # the marketing home; we hide it from everyone now so all visitors —
    # signed-in admin or anonymous — see the same generic fleet below.
    @agents = []

    # Mock "fleet" — smoke-and-mirrors. Shown to the public as the agents list,
    # stacked under the real team list for admins. Statuses animate client-side.
    @mock_agents = 10.times.map do |i|
      Agent.new(
        name: format("%03d", i + 1),
        role: MOCK_AGENT_ROLES[i],
        status: %w[online online online busy offline].sample,
        avatar_color: "orange",
        current_task: nil
      )
    end

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
