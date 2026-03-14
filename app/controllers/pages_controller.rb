class PagesController < ApplicationController
  allow_unauthenticated_access

  def home
    @recent_jobs = Job.active.recent.limit(6)
    @recent_posts = Post.published.limit(3)
  end
end
