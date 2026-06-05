class JobsController < ApplicationController
  FREE_JOB_VIEWS = 5

  RANGE_MAP = { "1d" => 1, "5d" => 5, "1w" => 7, "3w" => 21, "1m" => 30, "3m" => 90, "6m" => 180 }.freeze
  DEFAULT_RANGE = "1m"

  def index
    @range = RANGE_MAP.key?(params[:range]) ? params[:range] : DEFAULT_RANGE
    @range_days = RANGE_MAP[@range]

    @tab = params[:tab].presence || "traditional"
    @fde = params[:fde].present?
    base = Job.active.where(posted_at: @range_days.days.ago..Time.current)
    # The FDE filter cuts across all three role classes (most FDE postings read
    # as AI/agent roles), so it bypasses the tab's role_class filter and scopes
    # the whole active set instead. Otherwise apply the selected tab.
    base = if @fde
      base.forward_deployed
    else
      case @tab
      when "ai"       then base.ai_augmented_only
      when "director" then base.agent_director
      else                 base.traditional
      end
    end
    base = base.search(params[:q]) if params[:q].present?
    base = base.by_skill(params[:skill]) if params[:skill].present?

    # Load user data early so counts can reflect hidden jobs
    if authenticated?
      saved = Current.user.saved_jobs.index_by(&:job_id)
      @saved_job_ids = saved.keys.to_set
      @applied_jobs = saved.select { |_, sj| sj.applied? }.transform_values(&:applied_at)
      @hidden_job_ids = Current.user.hidden_jobs.pluck(:job_id).to_set
    else
      @saved_job_ids = Set.new
      @applied_jobs = {}
      @hidden_job_ids = Set.new
    end

    # Compute counts excluding hidden jobs for authenticated users
    hide_filter = @hidden_job_ids.any? && params[:show_hidden] != "1"
    visible_base = hide_filter ? base.where.not(id: @hidden_job_ids) : base

    @category_counts = visible_base.group(:category).count
    @total_count = @category_counts.values.sum
    @new_today_count = visible_base.posted_today.count
    @remote_count = visible_base.remote.count

    if params[:category] == "new_today"
      @jobs = base.posted_today
    elsif params[:category] == "remote"
      @jobs = base.remote
    elsif params[:category].present?
      @jobs = base.by_category(params[:category])
    else
      @jobs = base
    end

    source_scope = hide_filter ? @jobs.where.not(id: @hidden_job_ids) : @jobs
    @source_counts = JobSource.where(job_id: source_scope.select(:id)).group(:source).count
    @jobs = @jobs.by_source(params[:source])

    case params[:sort]
    when "salary_desc"
      @jobs = @jobs.by_salary_desc
    when "salary_asc"
      @jobs = @jobs.by_salary_asc
    else
      @jobs = @jobs.recent
    end

    @jobs = @jobs.page(params[:page]) if @jobs.respond_to?(:page)

    if params[:saved] == "1" && @saved_job_ids.any?
      @jobs = @jobs.where(id: @saved_job_ids)
    end

    if hide_filter
      @jobs = @jobs.where.not(id: @hidden_job_ids)
    end

    @jobs = @jobs.includes(:job_sources)

    # Trend data: daily job counts scoped to selected range (cached 1 hour)
    end_date = Time.current.to_date
    start_date = end_date - @range_days.days
    @trend_labels = (start_date..end_date).to_a

    utc_offset = Time.current.utc_offset / 3600
    offset_str = format("%+d hours", utc_offset)

    trend_cache = Rails.cache.fetch("job_trends/v4/#{@range}/#{end_date}", expires_in: 1.hour) do
      trend_base = Job.active.where("posted_at >= ?", start_date.in_time_zone.beginning_of_day)

      auto_counts = trend_base.traditional.group("date(posted_at, '#{offset_str}')").count
      ai_counts = trend_base.ai_augmented_only.group("date(posted_at, '#{offset_str}')").count
      director_counts = trend_base.agent_director.group("date(posted_at, '#{offset_str}')").count

      {
        auto: @trend_labels.map { |d| auto_counts[d.to_s] || 0 },
        ai: @trend_labels.map { |d| ai_counts[d.to_s] || 0 },
        director: @trend_labels.map { |d| director_counts[d.to_s] || 0 }
      }
    end

    @trend_data_auto = trend_cache[:auto]
    @trend_data_ai = trend_cache[:ai]
    @trend_data_director = trend_cache[:director]

    @top_skills = Rails.cache.fetch("jobs/top_skills/#{@tab}/#{@range}/#{Date.current}", expires_in: 1.hour) do
      skills_scope = Job.active.where(posted_at: @range_days.days.ago..Time.current)
      skills_scope = case @tab
      when "ai"       then skills_scope.ai_augmented_only
      when "director" then skills_scope.agent_director
      else                 skills_scope.traditional
      end
      SkillExtractor.top_skills(skills_scope, limit: 10)
    end
    @ai_demand_meter = Job.ai_demand_meter(window_days: @range_days)
    @salary_trad = Job.salary_stats(role_class: "traditional", window_days: @range_days)
    @salary_ai = Job.salary_stats(role_class: "ai_augmented", window_days: @range_days)
    @salary_director = Job.salary_stats(role_class: "agent_director", window_days: @range_days)
  end

  # Personalized "For You" feed — JobMatch scores ranked for Rich. Auth-only
  # (so admin-only via enforce_workspace_scope). See JobMatcher / RankJobMatchesJob.
  def for_me
    @profile = JobMatcher.profile["candidate"] || {}
    @focus   = params[:focus].presence

    saved = Current.user.saved_jobs.index_by(&:job_id)
    @saved_job_ids  = saved.keys.to_set
    @applied_jobs   = saved.select { |_, sj| sj.applied? }.transform_values(&:applied_at)
    @hidden_job_ids = Current.user.hidden_jobs.pluck(:job_id).to_set

    scope = JobMatch.ranked.preload(job: :job_sources).joins(:job).merge(Job.active)
    scope = scope.where.not(job_id: @hidden_job_ids) if @hidden_job_ids.any? && params[:show_hidden] != "1"
    scope = case @focus
    when "agent"      then scope.merge(Job.agent_director)
    when "ai"         then scope.merge(Job.ai_augmented_only)
    when "automation" then scope.merge(Job.traditional)
    when "dream"      then scope.where(job_matches: { is_dream: true })
    else scope
    end
    # "Remote only" = genuinely remote, so exclude hybrid roles (e.g. "Hybrid 3
    # days/week / Remote") that match Job.remote merely because the title says
    # "Remote" — useless for a remote-from-Rochester search.
    scope = scope.merge(Job.remote).where("LOWER(jobs.title) NOT LIKE ?", "%hybrid%") if params[:remote] == "1"
    @matches = scope.limit(120).to_a

    active_matches = JobMatch.joins(:job).merge(Job.active)
    @counts = {
      all:        active_matches.count,
      agent:      active_matches.merge(Job.agent_director).count,
      ai:         active_matches.merge(Job.ai_augmented_only).count,
      automation: active_matches.merge(Job.traditional).count,
      dream:      active_matches.where(job_matches: { is_dream: true }).count
    }
    @last_ranked_at = JobMatch.maximum(:computed_at)
  end

  # Apply kit for one match: a tailored cover letter (generated on demand the
  # first time, or when params[:regenerate]) + Rich's standard screening answers.
  # Auth-only; renders into the card's turbo frame. He reviews + submits himself.
  def apply_kit
    @job   = Job.find(params[:id])
    @match = JobMatch.find_or_create_by!(job_id: @job.id) { |m| m.score = 0 }
    @app   = JobMatcher.profile["application"] || {}

    if @match.cover_letter.blank? || params[:regenerate].present?
      CoverLetterGenerator.generate!(@match)
      @match.reload
    end

    render partial: "jobs/apply_kit", locals: { job: @job, match: @match, app: @app }
  end

  def show
    @job = Job.includes(:job_sources).find(params[:id])

    if authenticated?
      if !Current.user.email_verified?
        redirect_to jobs_path, alert: "Please verify your email to view job details. Check your inbox for a verification link."
        return
      end
      @saved_job = Current.user.saved_jobs.find_by(job: @job)
      @saved = @saved_job.present?
      @applied = @saved_job&.applied?
    else
      # Soft gate: allow N free job views for unauthenticated visitors,
      # then prompt for signup. Bots are exempt so SEO is unaffected.
      unless bot_request?
        viewed = (session[:viewed_job_ids] ||= [])
        viewed << @job.id unless viewed.include?(@job.id)
        viewed.shift while viewed.length > 50  # cap session size
        session[:viewed_job_ids] = viewed

        if viewed.length > FREE_JOB_VIEWS
          redirect_to soft_gate_path(next: request.fullpath, source: "job_view_limit")
          nil
        end
      end
    end
  end

  def today
    redirect_to jobs_path(category: "new_today")
  end

  def globe
    @globe_data = Job.active
      .where.not(latitude: nil, longitude: nil)
      .group(:latitude, :longitude, :location)
      .count
      .map { |(lat, lng, location), count| { lat: lat, lng: lng, location: location, count: count } }
  end
end
