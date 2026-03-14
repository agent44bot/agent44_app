class JobsController < ApplicationController
  allow_unauthenticated_access

  def index
    @jobs = Job.active.recent
    @jobs = @jobs.by_category(params[:category]) if params[:category].present?
    @jobs = @jobs.search(params[:q]) if params[:q].present?
    @jobs = @jobs.page(params[:page]) if @jobs.respond_to?(:page)
  end

  def show
    @job = Job.find(params[:id])
  end
end
