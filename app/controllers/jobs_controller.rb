class JobsController < ApplicationController
  allow_unauthenticated_access

  def index
    base = Job.active
    base = base.search(params[:q]) if params[:q].present?

    @category_counts = base.group(:category).count
    @total_count = @category_counts.values.sum
    @new_today_count = base.posted_today.count

    if params[:category] == "new_today"
      @jobs = base.posted_today
    elsif params[:category].present?
      @jobs = base.by_category(params[:category])
    else
      @jobs = base
    end

    @source_counts = @jobs.group(:source).count
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

    if authenticated?
      saved = Current.session.user.saved_jobs.index_by(&:job_id)
      @saved_job_ids = saved.keys.to_set
      @applied_jobs = saved.select { |_, sj| sj.applied? }.transform_values(&:applied_at)
    else
      @saved_job_ids = Set.new
      @applied_jobs = {}
    end

    if params[:saved] == "1" && @saved_job_ids.any?
      @jobs = @jobs.where(id: @saved_job_ids)
    end

    # Trend data: daily job counts from March 15 forward (cached 6 hours)
    start_date = Date.new(2026, 3, 15)
    end_date = Time.current.to_date
    @trend_labels = (start_date..end_date).to_a

    utc_offset = Time.current.utc_offset / 3600
    offset_str = format("%+d hours", utc_offset)

    trend_cache = Rails.cache.fetch("job_trends/#{end_date}", expires_in: 6.hours) do
      auto_base = Job.active.where("posted_at >= ?", start_date.in_time_zone.beginning_of_day).where.not(category: "ai")
      auto_counts = auto_base.group("date(posted_at, '#{offset_str}')").count

      ai_base = Job.active.where("posted_at >= ?", start_date.in_time_zone.beginning_of_day).where(category: "ai")
      ai_counts = ai_base.group("date(posted_at, '#{offset_str}')").count

      {
        auto: @trend_labels.map { |d| auto_counts[d.to_s] || 0 },
        ai: @trend_labels.map { |d| ai_counts[d.to_s] || 0 }
      }
    end

    @trend_data_auto = trend_cache[:auto]
    @trend_data_ai = trend_cache[:ai]
  end

  def show
    @job = Job.find(params[:id])
    if authenticated?
      @saved_job = Current.session.user.saved_jobs.find_by(job: @job)
      @saved = @saved_job.present?
      @applied = @saved_job&.applied?
    end
  end
end
