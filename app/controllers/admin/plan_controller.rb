module Admin
  # Owner-only plans: checkable to-do lists. Plan text and completion state
  # live in OwnerPlan (kv_settings under "<plan key>:done:<step_id>").
  class PlanController < BaseController
    OWNER_EMAIL = "botwhisperer@hey.com".freeze

    before_action :require_owner

    def show
      @plans = OwnerPlan.all
      @plan = OwnerPlan.find(params[:plan]) || OwnerPlan.default
      @done = @plan.steps.to_h { |st| [ st.id, st.done_at ] }
      @total = @plan.total
      @completed = @plan.completed
    end

    # Toggle a step. Legacy callers without a plan param resolve to the June
    # plan, which was the only plan when the toggle route shipped.
    def toggle
      plan = params[:plan].present? ? OwnerPlan.find(params[:plan]) : OwnerPlan.find("june-2026")
      id = params[:step_id].to_s
      return head :unprocessable_entity unless plan&.step?(id)

      plan.toggle!(id)
      redirect_to admin_plan_path(plan: plan.slug)
    end

    private

    def require_owner
      unless Current.user&.email_address == OWNER_EMAIL
        redirect_to root_path, alert: "Not authorized."
      end
    end
  end
end
