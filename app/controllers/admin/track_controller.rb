module Admin
  class TrackController < BaseController
    OWNER_EMAIL = "botwhisperer@hey.com".freeze

    before_action :require_owner

    def lora
      @user = User.find_by(email_address: "lora.downie@nykitchen.com")
      return redirect_to(admin_users_path, alert: "No user with that email yet.") unless @user

      tz = "Eastern Time (US & Canada)"
      now_et = Time.current.in_time_zone(tz)
      today_start = now_et.beginning_of_day.utc
      week_start  = (now_et - 6.days).beginning_of_day.utc
      d30_start   = (now_et - 29.days).beginning_of_day.utc

      @range = %w[today week 30d all].include?(params[:range]) ? params[:range] : "week"
      since = case @range
              when "today" then today_start
              when "week"  then week_start
              when "30d"   then d30_start
              else              Time.at(0)
              end

      scope = PageView.where(user_id: @user.id)

      @page_views = scope.where("created_at >= ?", since).order(created_at: :desc).limit(500).to_a
      @range_truncated = scope.where("created_at >= ?", since).count > 500

      @counts = {
        today: scope.where("created_at >= ?", today_start).count,
        week:  scope.where("created_at >= ?", week_start).count,
        d30:   scope.where("created_at >= ?", d30_start).count,
        all:   scope.count
      }

      @last_seen = scope.order(created_at: :desc).first

      # Top paths in the selected window
      @top_paths = scope.where("created_at >= ?", since)
                        .group(:path)
                        .order(Arel.sql("COUNT(*) DESC"))
                        .limit(8)
                        .count

      # Distinct sessions in the selected window
      @session_count = scope.where("created_at >= ?", since).distinct.count(:session_id)
    end

    private

    def require_owner
      unless Current.user&.email_address == OWNER_EMAIL
        redirect_to root_path, alert: "Not authorized."
      end
    end
  end
end
