module Admin
  class TrackController < BaseController
    OWNER_EMAIL = "botwhisperer@hey.com".freeze

    # Anonymous hits to these paths are overwhelmingly bot probes that slip
    # past the UA filter (749 /sign_in + 344 / in one week vs a handful of
    # real visitors). Hidden from the anonymous rollup and drill-in so the
    # signed-out view shows actual people. Signed-in views are unaffected.
    ANON_NOISE_PATHS = [ "/", "/sign_in" ].freeze

    before_action :require_owner

    def index
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

      # Chips for the user picker: every signed-in user with tracked
      # activity, ordered by most-recent page view (capped at 12).
      tracked_user_ids = PageView.where.not(user_id: nil)
                                 .group(:user_id)
                                 .order(Arel.sql("MAX(created_at) DESC"))
                                 .limit(12)
                                 .count.keys
      users_by_id = User.where(id: tracked_user_ids).index_by(&:id)
      @filter_users = tracked_user_ids.filter_map { |uid| users_by_id[uid] }

      # Chips are ordered by all-time recency but the table respects @range,
      # so a chip can promise a user the table doesn't show. Dim those.
      @active_user_ids = PageView.where(user_id: tracked_user_ids)
                                 .where("created_at >= ?", since)
                                 .distinct.pluck(:user_id).to_set
      @anon_active = anon_page_views.where("created_at >= ?", since).exists?

      # "anonymous" drills into signed-out traffic (user_id is NULL).
      @anonymous = params[:user_id] == "anonymous"
      @user = User.find_by(id: params[:user_id]) if params[:user_id].present? && !@anonymous

      if @user || @anonymous
        scope = @anonymous ? anon_page_views : PageView.where(user_id: @user.id)

        @page_views = scope.where("created_at >= ?", since).order(created_at: :desc).limit(500).to_a
        @range_truncated = scope.where("created_at >= ?", since).count > 500

        @counts = {
          today: scope.where("created_at >= ?", today_start).count,
          week:  scope.where("created_at >= ?", week_start).count,
          d30:   scope.where("created_at >= ?", d30_start).count,
          all:   scope.count
        }

        @last_seen     = scope.order(created_at: :desc).first
        @top_paths     = scope.where("created_at >= ?", since)
                              .group(:path)
                              .order(Arel.sql("COUNT(*) DESC"))
                              .limit(8)
                              .count
        @session_count = scope.where("created_at >= ?", since).distinct.count(:session_id)
      else
        # Overview: hits / sessions / last-seen per tracked user in the window.
        rows = PageView.where.not(user_id: nil)
                       .where("created_at >= ?", since)
                       .group(:user_id)
                       .pluck(
                         :user_id,
                         Arel.sql("COUNT(*)"),
                         Arel.sql("COUNT(DISTINCT session_id)"),
                         Arel.sql("MAX(created_at)")
                       )

        users_in_window = User.where(id: rows.map(&:first)).index_by(&:id)

        @user_summary = rows.filter_map do |uid, hits, sessions, last_seen_at|
          user = users_in_window[uid]
          next unless user
          { user: user, hits: hits, sessions: sessions, last_seen_at: last_seen_at }
        end.sort_by { |row| -row[:hits] }

        # Signed-out traffic gets one rollup row at the bottom of the table.
        anon = anon_page_views.where("created_at >= ?", since)
        anon_hits = anon.count
        if anon_hits.positive?
          @anon_summary = {
            hits:         anon_hits,
            sessions:     anon.distinct.count(:session_id),
            last_seen_at: anon.maximum(:created_at)
          }
        end
      end
    end

    private

    def anon_page_views
      PageView.where(user_id: nil).where.not(path: ANON_NOISE_PATHS)
    end

    def require_owner
      unless Current.user&.email_address == OWNER_EMAIL
        redirect_to root_path, alert: "Not authorized."
      end
    end
  end
end
