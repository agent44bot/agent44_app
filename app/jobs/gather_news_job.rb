require "rake"

class GatherNewsJob < ApplicationJob
  queue_as :default

  def perform
    articles_before = NewsArticle.count
    digest_existed = NewsDigest.exists?(date: Date.current)

    Rails.application.load_tasks unless Rake::Task.task_defined?("newsletter:gather_news")
    Rake::Task["newsletter:gather_news"].reenable
    Rake::Task["newsletter:gather_news"].invoke

    new_articles = NewsArticle.count - articles_before
    digest_now = NewsDigest.exists?(date: Date.current)

    if !digest_now
      Notification.notify!(
        level: "warning",
        source: "gather_news",
        title: "News digest not generated",
        body: "newsletter:gather_news ran but no NewsDigest exists for #{Date.current}. New articles fetched: #{new_articles}.",
        telegram: true
      )
    elsif !digest_existed
      Notification.notify!(
        level: "success",
        source: "gather_news",
        title: "Daily digest published",
        body: "Fetched #{new_articles} new articles and generated digest for #{Date.current}."
      )
    end
  rescue => e
    Notification.notify!(
      level: "error",
      source: "gather_news",
      title: "GatherNewsJob crashed",
      body: "#{e.class}: #{e.message}\n\n#{e.backtrace&.first(5)&.join("\n")}",
      telegram: true
    )
    raise
  end
end
