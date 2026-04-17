module Admin
  class SmokeRunsController < BaseController
    # DELETE /admin/smoke_runs/:id
    # Remove a single smoke-test-run row from the dashboard (e.g. after a known
    # flake). Admin-only; base controller enforces auth.
    def destroy
      run = SmokeTestRun.find(params[:id])
      run.destroy!
      Rails.cache.delete("smoke_runs/recent")
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.remove(run) }
        format.html { redirect_to kitchen_path, notice: "Smoke test run removed." }
      end
    rescue ActiveRecord::RecordNotFound
      redirect_to kitchen_path, alert: "Smoke test run not found."
    end
  end
end
