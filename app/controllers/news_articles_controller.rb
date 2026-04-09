class NewsArticlesController < ApplicationController
  allow_unauthenticated_access

  def index
    @date = if params[:date].present?
      Date.parse(params[:date])
    else
      Time.current.to_date
    end

    @articles = NewsArticle.where(
      published_at: @date.beginning_of_day..@date.end_of_day
    ).order(published_at: :desc)

    # If no articles for today, show most recent day that has articles
    if @articles.empty? && params[:date].blank?
      latest = NewsArticle.order(published_at: :desc).first
      if latest
        @date = latest.published_at.to_date
        @articles = NewsArticle.where(
          published_at: @date.beginning_of_day..@date.end_of_day
        ).order(published_at: :desc)
      end
    end

    @grouped = @articles.group_by(&:source)
    @digest = NewsDigest.find_by(date: @date)
    @prev_date = NewsArticle.where("published_at < ?", @date.beginning_of_day)
                            .order(published_at: :desc).first&.published_at&.to_date
    @next_date = NewsArticle.where("published_at > ?", @date.end_of_day)
                            .order(published_at: :asc).first&.published_at&.to_date
  end
end
