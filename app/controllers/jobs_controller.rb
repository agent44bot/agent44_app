class JobsController < ApplicationController
  allow_unauthenticated_access

  def index
    base = Job.active.recent
    base = base.search(params[:q]) if params[:q].present?

    @category_counts = base.group(:category).count
    @total_count = @category_counts.values.sum

    @jobs = params[:category].present? ? base.by_category(params[:category]) : base
    @jobs = @jobs.page(params[:page]) if @jobs.respond_to?(:page)
  end

  def show
    @job = Job.find(params[:id])
  end
end
