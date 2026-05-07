module Admin
  class AiCostsController < BaseController
    def index
      now = Time.zone.now
      @month_start = now.beginning_of_month

      logs_this_month = AiCallLog.where("created_at >= ?", @month_start)
      @summary_by_source = AiCallLog.summary_by_source(logs_this_month)
      @month_total       = AiCallLog.total_cost_dollars(logs_this_month)

      @nyk_total_month = AiCallLog.total_cost_dollars(logs_this_month.where(source: AiCallLog::NYK_SOURCES))
      @nyk_total_all   = AiCallLog.total_cost_dollars(AiCallLog.where(source: AiCallLog::NYK_SOURCES))

      @recent = AiCallLog.order(created_at: :desc).limit(50).includes(:user)
    end
  end
end
