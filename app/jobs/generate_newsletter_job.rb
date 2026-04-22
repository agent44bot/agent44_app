require "rake"

class GenerateNewsletterJob < ApplicationJob
  queue_as :default

  def perform
    posts_before = Post.count

    Rails.application.load_tasks unless Rake::Task.task_defined?("newsletter:generate")
    Rake::Task["newsletter:generate"].reenable
    Rake::Task["newsletter:generate"].invoke

    new_posts = Post.count - posts_before

    if new_posts > 0
      post = Post.order(created_at: :desc).first
      Notification.notify!(
        level: "success",
        source: "newsletter_generate",
        title: "Scout published a new pulse post",
        body: "\"#{post.title}\" — /pulse/#{post.slug}"
      )
    else
      Notification.notify!(
        level: "warning",
        source: "newsletter_generate",
        title: "Newsletter generate ran but no post was created",
        telegram: true
      )
    end
  rescue => e
    Notification.notify!(
      level: "error",
      source: "newsletter_generate",
      title: "GenerateNewsletterJob crashed",
      body: "#{e.class}: #{e.message}\n\n#{e.backtrace&.first(5)&.join("\n")}",
      telegram: true
    )
    raise
  end
end
