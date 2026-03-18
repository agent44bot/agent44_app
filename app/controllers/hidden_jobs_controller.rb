class HiddenJobsController < ApplicationController
  before_action :set_job

  def create
    Current.session.user.hidden_jobs.find_or_create_by(job: @job)
    redirect_back fallback_location: jobs_path
  end

  def destroy
    Current.session.user.hidden_jobs.find_by(job: @job)&.destroy
    redirect_back fallback_location: jobs_path
  end

  private

  def set_job
    @job = Job.find(params[:job_id])
  end
end
