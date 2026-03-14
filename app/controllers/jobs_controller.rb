class JobsController < ApplicationController
  allow_unauthenticated_access

  def index
    base = Job.active.recent
    base = base.search(params[:q]) if params[:q].present?

    @category_counts = base.group(:category).count
    @total_count = @category_counts.values.sum

    @jobs = params[:category].present? ? base.by_category(params[:category]) : base
    @jobs = @jobs.page(params[:page]) if @jobs.respond_to?(:page)

    # Trend data: daily job counts for the last 30 days
    thirty_days_ago = 30.days.ago.beginning_of_day
    trend_base = Job.active.where("posted_at >= ?", thirty_days_ago)
    daily_counts = trend_base.group("date(posted_at)").count
    @trend_labels = (30.downto(0)).map { |i| i.days.ago.to_date }
    @trend_data = @trend_labels.map { |d| daily_counts[d.to_s] || 0 }
  end

  def show
    @job = Job.find(params[:id])
  end
end
