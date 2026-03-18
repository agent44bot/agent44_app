class PostsController < ApplicationController
  allow_unauthenticated_access

  def index
    @posts = Post.published
  end

  def show
    scope = authenticated? && Current.session.user.admin? ? Post.all : Post.published
    @post = scope.find_by!(slug: params[:id])
  end
end
