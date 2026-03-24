class HiddenJobsController < ApplicationController
  before_action :set_job

  def create
    Current.session.user.hidden_jobs.find_or_create_by(job: @job)

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@job)) }
      format.html { redirect_back fallback_location: jobs_path }
    end
  end

  def destroy
    Current.session.user.hidden_jobs.find_by(job: @job)&.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@job)) }
      format.html { redirect_back fallback_location: jobs_path }
    end
  end

  private

  def set_job
    @job = Job.find(params[:job_id])
  end
end
