module Admin
  class PostsController < BaseController
    before_action :set_post, only: %i[edit update destroy]

    def index
      @posts = Post.order(updated_at: :desc)
    end

    def new
      @post = Post.new
    end

    def create
      @post = Current.session.user.posts.build(post_params)
      if @post.save
        redirect_to admin_posts_path, notice: "Post created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @post.update(post_params)
        redirect_to admin_posts_path, notice: "Post updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @post.destroy
      redirect_to admin_posts_path, notice: "Post deleted."
    end

    private

    def set_post
      @post = Post.find(params[:id])
    end

    def post_params
      params.require(:post).permit(:title, :slug, :body, :published, :published_at)
    end
  end
end
