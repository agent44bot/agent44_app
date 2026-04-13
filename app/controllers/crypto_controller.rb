class CryptoController < ApplicationController
  before_action :require_admin

  RANGE_MAP = { "1d" => 1, "5d" => 5, "1w" => 7, "3w" => 21, "1m" => 30, "3m" => 90, "6m" => 180 }.freeze
  DEFAULT_RANGE = "1m"

  def index
    @range = RANGE_MAP.key?(params[:range]) ? params[:range] : DEFAULT_RANGE
    @range_days = RANGE_MAP[@range]

    @tab = params[:tab].presence || "security"

    base = Job.active.where(posted_at: @range_days.days.ago..Time.current)

    # Counts per silo
    @security_count = base.security_engineer.count
    @crypto_count = base.crypto_trustless.count
    @secfirst_count = base.security_first.count

    # Current tab's jobs
    @jobs = case @tab
            when "crypto"   then base.crypto_trustless
            when "secfirst" then base.security_first
            else                 base.security_engineer
            end.recent.limit(50)

    # Trend data (cached)
    end_date = Time.current.to_date
    start_date = end_date - @range_days.days
    @trend_labels = (start_date..end_date).to_a

    utc_offset = Time.current.utc_offset / 3600
    offset_str = format("%+d hours", utc_offset)

    @trends = Rails.cache.fetch("crypto/trends/v1/#{@range}/#{end_date}", expires_in: 1.hour) do
      trend_base = Job.active.where("posted_at >= ?", start_date.in_time_zone.beginning_of_day)
      {
        security: @trend_labels.map { |d| trend_base.security_engineer.where("date(posted_at, '#{offset_str}') = ?", d.to_s).count },
        crypto: @trend_labels.map { |d| trend_base.crypto_trustless.where("date(posted_at, '#{offset_str}') = ?", d.to_s).count },
        secfirst: @trend_labels.map { |d| trend_base.security_first.where("date(posted_at, '#{offset_str}') = ?", d.to_s).count }
      }
    end

    # Skills per tab (cached)
    @top_skills = Rails.cache.fetch("crypto/skills/#{@tab}/#{@range}/#{Date.current}", expires_in: 1.hour) do
      scope = case @tab
              when "crypto"   then base.crypto_trustless
              when "secfirst" then base.security_first
              else                 base.security_engineer
              end
      SecuritySkillExtractor.top_skills(scope, limit: 10)
    end

    # Salary stats
    @salary = Rails.cache.fetch("crypto/salary/#{@tab}/#{@range}/#{Date.current}", expires_in: 1.hour) do
      scope = case @tab
              when "crypto"   then base.crypto_trustless
              when "secfirst" then base.security_first
              else                 base.security_engineer
              end
      values = scope.where.not(salary: [nil, ""]).pluck(:salary).filter_map { |s| Job.parse_salary_midpoint(s) }.sort
      n = values.size
      pct = ->(p) { n.zero? ? nil : values[((n - 1) * p).round] }
      { total: scope.count, with_salary: n, median: pct.call(0.5), p25: pct.call(0.25), p75: pct.call(0.75) }
    end
  end

  private

  def require_admin
    unless authenticated? && Current.session.user.admin?
      redirect_to root_path, alert: "Not found."
    end
  end
end
