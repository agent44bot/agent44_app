module Admin
  class DashboardController < BaseController
    def index
      @period = params[:period] || "today"

      cache_key = "admin_dashboard/#{@period}/#{Date.current}"
      cached = Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
        scope = page_views_for_period

        {
          total_views: scope.count,
          unique_visitors: scope.distinct.count(:session_id),
          unique_ips: scope.distinct.count(:ip_address),
          registered_users: User.where(role: "member").count,
          new_users: User.where(role: "member").where(created_at: date_range).count,
          trend_data: PageView.where(created_at: 30.days.ago..Time.current)
                              .group("DATE(created_at)")
                              .order(Arel.sql("DATE(created_at)"))
                              .count,
          top_pages: scope.group(:path).order("count_all DESC").limit(10).count,
          device_breakdown: scope.group(:device_type).count,
          top_referrers: scope.where.not(referrer: [nil, ""])
                              .group(:referrer)
                              .order("count_all DESC")
                              .limit(10)
                              .count,
          top_countries: scope.where.not(country: [nil, ""])
                              .group(:country)
                              .order("count_all DESC")
                              .limit(10)
                              .count
        }
      end

      cached.each { |key, value| instance_variable_set("@#{key}", value) }
      @recent_users = User.order(created_at: :desc).limit(10)
    end

    private

    def page_views_for_period
      case params[:period]
      when "week" then PageView.this_week
      when "month" then PageView.this_month
      else PageView.today
      end
    end

    def date_range
      case params[:period]
      when "week" then Date.current.beginning_of_week..Time.current
      when "month" then Date.current.beginning_of_month..Time.current
      else Date.current.all_day
      end
    end
  end
end
