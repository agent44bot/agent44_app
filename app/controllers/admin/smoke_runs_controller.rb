module Admin
  class SmokeRunsController < BaseController
    # DELETE /admin/smoke_runs/:id
    # Remove a single smoke-test-run row from the dashboard (e.g. after a known
    # flake). Admin-only; base controller enforces auth.
    def destroy
      SmokeTestRun.find(params[:id]).destroy!
      Rails.cache.delete("smoke_runs/recent")
      redirect_to kitchen_path, notice: "Smoke test run removed."
    rescue ActiveRecord::RecordNotFound
      redirect_to kitchen_path, alert: "Smoke test run not found."
    end
  end
end
