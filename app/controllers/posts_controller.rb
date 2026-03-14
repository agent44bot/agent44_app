class PostsController < ApplicationController
  allow_unauthenticated_access

  def index
    @posts = Post.published
  end

  def show
    @post = Post.published.find_by!(slug: params[:id])
  end
end
