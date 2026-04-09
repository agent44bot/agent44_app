class PagesController < ApplicationController
  allow_unauthenticated_access

  def home
    @recent_jobs = Job.active.recent.limit(6)
    @todays_jobs = Job.active.posted_today.recent.limit(5)
    @digest = NewsDigest.order(date: :desc).first
    @recent_news = NewsArticle.recent.limit(3)
    @recent_posts = Post.published.limit(3)
    @ai_demand_meter = Job.ai_demand_meter
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
