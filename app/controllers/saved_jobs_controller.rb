class SavedJobsController < ApplicationController
  before_action :set_job, only: [ :create, :destroy, :toggle_applied ]

  def index
    @saved_jobs = Current.session.user.saved_job_listings.active.order(posted_at: :desc)
  end

  def create
    Current.session.user.saved_jobs.find_or_create_by(job: @job)
    redirect_back fallback_location: jobs_path
  end

  def destroy
    Current.session.user.saved_jobs.find_by(job: @job)&.destroy
    redirect_back fallback_location: saved_jobs_path
  end

  def toggle_applied
    saved_job = Current.session.user.saved_jobs.find_or_create_by(job: @job)
    saved_job.toggle_applied!
    redirect_back fallback_location: job_path(@job)
  end

  private

  def set_job
    @job = Job.find(params[:job_id])
  end
end
