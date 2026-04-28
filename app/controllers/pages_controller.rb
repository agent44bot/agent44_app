class PagesController < ApplicationController
  allow_unauthenticated_access

  MOCK_AGENT_ROLES = [
    "Scout", "Email Copywriter", "Watchtower", "Social Media Copywriter", "Crawler",
    "Digest", "Secret Agent", "Analyzer", "QA Runner", "Replayer"
  ].freeze

  def home
    real_agents = Agent.ordered.to_a
    @agents = (authenticated? && Current.session.user.admin?) ? real_agents : []

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
    nyk_runs = SmokeTestRun.for_name("nykitchen").recent
    @nyk_latest_run = nyk_runs.first
    @nyk_total_runs = nyk_runs.count
    @nyk_pass_rate = nyk_runs.any? ? (nyk_runs.where(status: "passed").count.to_f / nyk_runs.count * 100).round : nil
    @nyk_total_cost = nyk_runs.sum(:cost_dollars)
    @can_see_nyk_pricing = authenticated? && (Current.session.user.admin? || Current.session.user.kitchen_only?)
  end

  def privacy
  end

  def lab
    unless authenticated? && Current.session.user.admin?
      redirect_to root_path, alert: "Not found." and return
    end
    @ai_demand_meter = Job.ai_demand_meter
    @director_salary = Job.salary_stats(role_class: "agent_director")
    @ai_salary = Job.salary_stats(role_class: "ai_augmented")
    @trad_salary = Job.salary_stats(role_class: "traditional")
    @recent_director_jobs = Job.active.agent_director.recent.limit(8)
    render layout: "admin"
  end
end
