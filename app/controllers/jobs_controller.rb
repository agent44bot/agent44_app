class JobsController < ApplicationController
  allow_unauthenticated_access only: :index

  def index
    base = Job.active.recent
    base = base.search(params[:q]) if params[:q].present?

    @category_counts = base.group(:category).count
    @total_count = @category_counts.values.sum
    @new_today_count = base.posted_today.count

    if params[:category] == "new_today"
      @jobs = base.posted_today
    elsif params[:category].present?
      @jobs = base.by_category(params[:category])
    else
      @jobs = base
    end
    @jobs = @jobs.page(params[:page]) if @jobs.respond_to?(:page)

    # Trend data: daily job counts from March 15 forward
    start_date = Date.new(2026, 3, 15)
    end_date = Date.current
    @trend_labels = (start_date..end_date).to_a

    # All test automation jobs (non-AI categories)
    auto_base = Job.active.where("posted_at >= ?", start_date.beginning_of_day).where.not(category: "ai")
    auto_counts = auto_base.group("date(posted_at)").count
    @trend_data_auto = @trend_labels.map { |d| auto_counts[d.to_s] || 0 }

    # AI jobs only
    ai_base = Job.active.where("posted_at >= ?", start_date.beginning_of_day).where(category: "ai")
    ai_counts = ai_base.group("date(posted_at)").count
    @trend_data_ai = @trend_labels.map { |d| ai_counts[d.to_s] || 0 }
  end

  def show
    @job = Job.find(params[:id])
  end
end
